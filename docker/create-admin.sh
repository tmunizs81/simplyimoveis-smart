#!/bin/bash
# ============================================================
# Cria/atualiza admin de forma compatível com GoTrue
# Uso: bash create-admin.sh email senha
# ============================================================

set -euo pipefail

EMAIL="${1:-}"
PASSWORD="${2:-}"

[ -z "$EMAIL" ] || [ -z "$PASSWORD" ] && echo "Uso: bash create-admin.sh email senha" && exit 1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

[ ! -f .env ] && echo "❌ .env não encontrado" && exit 1

read_env() { grep -E "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"; }

POSTGRES_DB=$(read_env "POSTGRES_DB")
POSTGRES_DB="${POSTGRES_DB:-simply_db}"
POSTGRES_PASSWORD=$(read_env "POSTGRES_PASSWORD")
SERVICE_ROLE_KEY=$(read_env "SERVICE_ROLE_KEY")
ANON_KEY=$(read_env "ANON_KEY")
KONG_HTTP_PORT=$(read_env "KONG_HTTP_PORT")
KONG_HTTP_PORT="${KONG_HTTP_PORT:-8000}"
DB_CONTAINER="simply-db"
AUTH_URL="http://127.0.0.1:${KONG_HTTP_PORT}/auth/v1"

[ -z "${POSTGRES_PASSWORD:-}" ] && echo "❌ POSTGRES_PASSWORD vazio" && exit 1
[ -z "${SERVICE_ROLE_KEY:-}" ] && echo "❌ SERVICE_ROLE_KEY vazio" && exit 1
[ -z "${ANON_KEY:-}" ] && echo "❌ ANON_KEY vazio" && exit 1

docker inspect -f '{{.State.Status}}' "$DB_CONTAINER" >/dev/null 2>&1 || { echo "❌ Container $DB_CONTAINER não encontrado"; exit 1; }

run_sql_cmd() {
  timeout 30s docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" \
    "$DB_CONTAINER" psql -v ON_ERROR_STOP=1 -w -h 127.0.0.1 -U supabase_admin -d "$POSTGRES_DB" "$@"
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

sql_escape() {
  printf '%s' "$1" | sed "s/'/''/g"
}

# Aguarda auth.users existir
AUTH_OK=""
for i in {1..30}; do
  AUTH_OK=$(run_sql_cmd -tA -c "SELECT to_regclass('auth.users') IS NOT NULL;" 2>/dev/null | tr -d '[:space:]' || true)
  [ "$AUTH_OK" = "t" ] && break
  sleep 2
done

if [ "$AUTH_OK" != "t" ]; then
  echo "❌ auth.users não existe. GoTrue ainda não migrou."
  exit 1
fi

echo "👤 Criando/atualizando admin: ${EMAIL}..."

EMAIL_JSON=$(json_escape "$EMAIL")
PASS_JSON=$(json_escape "$PASSWORD")
CREATE_BODY="{\"email\":\"${EMAIL_JSON}\",\"password\":\"${PASS_JSON}\",\"email_confirm\":true}"

# 1) Tenta criar via API admin (fonte da verdade do GoTrue)
CREATE_HTTP=$(curl -sS -m 30 -o /tmp/create_admin_resp.$$ -w "%{http_code}" \
  -X POST "${AUTH_URL}/admin/users" \
  -H "apikey: ${SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" \
  -H "Content-Type: application/json" \
  -d "$CREATE_BODY" || true)

if [ "$CREATE_HTTP" = "200" ] || [ "$CREATE_HTTP" = "201" ]; then
  echo "✅ Usuário criado via Auth API"
else
  RESP=$(cat /tmp/create_admin_resp.$$ 2>/dev/null || true)

  # Se usuário já existe, atualiza senha e confirma email
  if echo "$RESP" | grep -Eiq "already|exists|registered|duplicate"; then
    ADMIN_UID=$(run_sql_cmd -tA -c "SELECT id FROM auth.users WHERE lower(email)=lower('$(sql_escape "$EMAIL")') LIMIT 1;" | tr -d '[:space:]')
    [ -z "$ADMIN_UID" ] && echo "❌ Usuário existe mas não foi encontrado em auth.users" && exit 1

    UPDATE_BODY="{\"password\":\"${PASS_JSON}\",\"email_confirm\":true}"
    UPDATE_HTTP=$(curl -sS -m 30 -o /tmp/update_admin_resp.$$ -w "%{http_code}" \
      -X PUT "${AUTH_URL}/admin/users/${ADMIN_UID}" \
      -H "apikey: ${SERVICE_ROLE_KEY}" \
      -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" \
      -H "Content-Type: application/json" \
      -d "$UPDATE_BODY" || true)

    if [ "$UPDATE_HTTP" != "200" ]; then
      echo "❌ Falha ao atualizar senha do usuário existente"
      cat /tmp/update_admin_resp.$$ 2>/dev/null || true
      exit 1
    fi

    echo "✅ Usuário existente atualizado via Auth API"
  else
    echo "❌ Falha ao criar usuário via Auth API (HTTP $CREATE_HTTP)"
    echo "$RESP"
    exit 1
  fi
fi

# 2) Garante role admin no app
ADMIN_UID=$(run_sql_cmd -tA -c "SELECT id FROM auth.users WHERE lower(email)=lower('$(sql_escape "$EMAIL")') LIMIT 1;" | tr -d '[:space:]')
[ -z "$ADMIN_UID" ] && echo "❌ Usuário não encontrado após create/update" && exit 1

run_sql_cmd -c "INSERT INTO public.user_roles (user_id, role) VALUES ('${ADMIN_UID}'::uuid, 'admin') ON CONFLICT (user_id, role) DO NOTHING;"

# 3) Smoke test de login real
LOGIN_BODY="{\"email\":\"${EMAIL_JSON}\",\"password\":\"${PASS_JSON}\"}"
LOGIN_HTTP=$(curl -sS -m 30 -o /tmp/admin_login_resp.$$ -w "%{http_code}" \
  -X POST "${AUTH_URL}/token?grant_type=password" \
  -H "apikey: ${ANON_KEY}" \
  -H "Content-Type: application/json" \
  -d "$LOGIN_BODY" || true)

if [ "$LOGIN_HTTP" != "200" ]; then
  echo "❌ Admin criado, mas login ainda falhou (HTTP $LOGIN_HTTP)"
  cat /tmp/admin_login_resp.$$ 2>/dev/null || true
  exit 1
fi

echo "✅ Admin ${EMAIL} configurado com sucesso!"
