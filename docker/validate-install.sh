#!/bin/bash
# ============================================================
# Valida se a stack Docker está operacional
# Versão: 2026-03-15-v3
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

[ ! -f .env ] && echo "❌ .env não encontrado." && exit 1

read_env_var() {
  grep -E "^${1}=" .env 2>/dev/null | head -1 | sed "s/^${1}=//" | tr -d '"' | tr -d "'"
}

KONG_PORT=$(read_env_var "KONG_HTTP_PORT")
KONG_PORT="${KONG_PORT:-8000}"
ANON_KEY=$(read_env_var "ANON_KEY")
SERVICE_ROLE_KEY=$(read_env_var "SERVICE_ROLE_KEY")
POSTGRES_PASSWORD=$(read_env_var "POSTGRES_PASSWORD")
POSTGRES_DB=$(read_env_var "POSTGRES_DB")
POSTGRES_DB="${POSTGRES_DB:-simply_db}"

[ -z "$ANON_KEY" ] || [ -z "$SERVICE_ROLE_KEY" ] && echo "❌ Chaves não definidas" && exit 1

ERRORS=0

check_container() {
  local container="$1"
  local state restarting
  state=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || true)
  restarting=$(docker inspect -f '{{.State.Restarting}}' "$container" 2>/dev/null || true)
  if [ "$state" != "running" ] || [ "$restarting" = "true" ]; then
    echo "❌ $container (status=$state, restarting=$restarting)"
    ERRORS=$((ERRORS+1))
    return 1
  fi
  echo "✅ $container"
}

echo "🔍 Containers..."
check_container simply-db || true
check_container simply-auth || true
check_container simply-rest || true
check_container simply-storage || true
check_container simply-functions || true
check_container simply-kong || true
check_container simply-frontend || true

# Verificar auth.users existe
echo "🔍 Schema auth..."
AUTH_CHECK=$(docker compose exec -T -e PGPASSWORD="${POSTGRES_PASSWORD}" db psql \
  -tA -U supabase_admin -d "$POSTGRES_DB" \
  -c "SELECT to_regclass('auth.users') IS NOT NULL;" 2>/dev/null | tr -d '[:space:]')

if [ "$AUTH_CHECK" != "t" ]; then
  echo "❌ auth.users não existe"
  ERRORS=$((ERRORS+1))
else
  echo "✅ auth.users existe"
fi

# Kong + Auth settings
echo "🔍 Autenticação via Kong..."
AUTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${KONG_PORT}/auth/v1/settings" \
  -H "apikey: ${ANON_KEY}" 2>/dev/null || echo "000")

if [ "$AUTH_STATUS" != "200" ]; then
  echo "❌ Auth/settings via Kong: HTTP $AUTH_STATUS"
  ERRORS=$((ERRORS+1))
else
  echo "✅ Auth/settings: HTTP 200"
fi

# Testar fluxo de login (deve retornar 400, NÃO 500)
LOGIN_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  "http://localhost:${KONG_PORT}/auth/v1/token?grant_type=password" \
  -H "apikey: ${ANON_KEY}" -H "Content-Type: application/json" \
  -d '{"email":"test@invalid.local","password":"wrong"}' 2>/dev/null || echo "000")

if [ "$LOGIN_STATUS" -ge 500 ] 2>/dev/null || [ "$LOGIN_STATUS" = "000" ]; then
  echo "❌ Fluxo de login: HTTP $LOGIN_STATUS (esperava 400)"
  ERRORS=$((ERRORS+1))
else
  echo "✅ Fluxo de login: HTTP $LOGIN_STATUS"
fi

# REST
REST_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${KONG_PORT}/rest/v1/" \
  -H "apikey: ${SERVICE_ROLE_KEY}" -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" 2>/dev/null || echo "000")

if [ "$REST_STATUS" -ge 500 ] 2>/dev/null || [ "$REST_STATUS" = "000" ]; then
  echo "❌ REST: HTTP $REST_STATUS"
  ERRORS=$((ERRORS+1))
else
  echo "✅ REST: HTTP $REST_STATUS"
fi

if [ "$ERRORS" -gt 0 ]; then
  echo "❌ $ERRORS problema(s) encontrado(s)."
  exit 1
fi

echo "🎉 Validação concluída com sucesso!"