#!/bin/bash
# ============================================================
# Cria o primeiro usuário admin (resiliente)
# Uso: bash create-admin.sh email@exemplo.com senha123
# ============================================================

set -euo pipefail

EMAIL=${1:-}
PASSWORD=${2:-}

if [ -z "$EMAIL" ] || [ -z "$PASSWORD" ]; then
  echo "Uso: bash create-admin.sh email@exemplo.com senha123"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f .env ]; then
  echo "❌ Arquivo .env não encontrado."
  exit 1
fi

# Lê variáveis do .env de forma segura (sem source)
read_env_var() {
  grep -E "^${1}=" .env 2>/dev/null | head -1 | sed "s/^${1}=//" | tr -d '"' | tr -d "'"
}

POSTGRES_DB=$(read_env_var "POSTGRES_DB")
POSTGRES_DB="${POSTGRES_DB:-simply_db}"
POSTGRES_PASSWORD=$(read_env_var "POSTGRES_PASSWORD")
KONG_PORT=$(read_env_var "KONG_HTTP_PORT")
KONG_PORT="${KONG_PORT:-8000}"
SERVICE_ROLE_KEY=$(read_env_var "SERVICE_ROLE_KEY")

if [ -z "$POSTGRES_PASSWORD" ]; then
  echo "❌ POSTGRES_PASSWORD não definido no .env"
  exit 1
fi

wait_container_running() {
  local container="$1"
  local timeout="${2:-60}"

  for _ in $(seq 1 "$timeout"); do
    local state restarting
    state=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || true)
    restarting=$(docker inspect -f '{{.State.Restarting}}' "$container" 2>/dev/null || true)

    if [ "$state" = "running" ] && [ "$restarting" != "true" ]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_auth_ready() {
  local api_key="$1"
  for _ in {1..60}; do
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${KONG_PORT}/auth/v1/settings" \
      -H "apikey: ${api_key}" 2>/dev/null || echo "000")
    if [ "$status" = "200" ]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

# Helper para rodar psql sem prompt de senha
run_psql() {
  docker compose exec -T -e PGPASSWORD="${POSTGRES_PASSWORD}" db psql \
    -v ON_ERROR_STOP=1 \
    -U supabase_admin \
    -d "$POSTGRES_DB" \
    "$@" 2>/dev/null || \
  docker compose exec -T db psql \
    -v ON_ERROR_STOP=1 \
    -U postgres \
    -d "$POSTGRES_DB" \
    "$@"
}

# 1) Garantir DB + roles internos sincronizados
echo "🔧 Sincronizando banco e credenciais..."
docker compose up -d db >/dev/null 2>&1
bash "$SCRIPT_DIR/sync-db-passwords.sh" --quiet

# 2) Recriar serviços dependentes
echo "🔄 Reiniciando serviços..."
docker compose up -d --force-recreate auth rest storage functions kong >/dev/null 2>&1

echo "⏳ Aguardando auth estabilizar..."
if ! wait_container_running simply-auth 90; then
  echo "❌ Container simply-auth não ficou estável."
  docker compose logs --tail=30 auth
  exit 1
fi

if ! wait_container_running simply-kong 60; then
  echo "❌ Container simply-kong não ficou estável."
  docker compose logs --tail=30 kong
  exit 1
fi

# Usa a chave ativa do container Kong
RUNTIME_SERVICE_KEY=$(docker compose exec -T kong printenv SUPABASE_SERVICE_KEY 2>/dev/null | tr -d '\r' || true)
API_SERVICE_KEY="${RUNTIME_SERVICE_KEY:-${SERVICE_ROLE_KEY:-}}"

if [ -z "$API_SERVICE_KEY" ]; then
  echo "❌ SERVICE_ROLE_KEY não encontrada."
  exit 1
fi

if ! wait_auth_ready "$API_SERVICE_KEY"; then
  echo "❌ Auth não respondeu. Logs:"
  docker compose logs --tail=30 auth
  exit 1
fi

echo "👤 Criando usuário admin: ${EMAIL}..."

RESPONSE_WITH_STATUS=$(curl -sS -w "\n%{http_code}" -X POST "http://localhost:${KONG_PORT}/auth/v1/admin/users" \
  -H "Authorization: Bearer ${API_SERVICE_KEY}" \
  -H "apikey: ${API_SERVICE_KEY}" \
  -H "Content-Type: application/json" \
  -d "{
    \"email\": \"${EMAIL}\",
    \"password\": \"${PASSWORD}\",
    \"email_confirm\": true
  }" 2>/dev/null)

HTTP_STATUS=$(echo "$RESPONSE_WITH_STATUS" | tail -n1)
USER_RESPONSE=$(echo "$RESPONSE_WITH_STATUS" | sed '$d')

USER_ID=""

if [ "$HTTP_STATUS" -ge 200 ] 2>/dev/null && [ "$HTTP_STATUS" -lt 300 ] 2>/dev/null; then
  USER_ID=$(echo "$USER_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4 || true)
else
  echo "⚠️  Resposta HTTP $HTTP_STATUS ao criar usuário."

  if echo "$USER_RESPONSE" | grep -qi "already been registered\|already exists"; then
    echo "ℹ️  Usuário já existe, buscando ID..."
  else
    echo "❌ Erro: $USER_RESPONSE"
    exit 1
  fi
fi

if [ -z "$USER_ID" ]; then
  USER_ID=$(run_psql -tA -c "SELECT id FROM auth.users WHERE email = '${EMAIL}' LIMIT 1;" | tr -d '[:space:]')
fi

if [ -z "$USER_ID" ]; then
  echo "❌ Não foi possível obter o ID do usuário."
  exit 1
fi

echo "✅ Usuário pronto: ${USER_ID}"

# Adiciona role admin
run_psql -c "INSERT INTO public.user_roles (user_id, role) VALUES ('${USER_ID}', 'admin') ON CONFLICT DO NOTHING;"

echo "✅ Role 'admin' atribuída."
echo ""
echo "🎉 Admin criado com sucesso!"
echo "   Email: ${EMAIL}"

SITE_DOMAIN=$(read_env_var "SITE_DOMAIN")
echo "   Acesse: https://${SITE_DOMAIN:-localhost}/admin"
