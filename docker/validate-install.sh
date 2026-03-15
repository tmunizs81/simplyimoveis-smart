#!/bin/bash
# ============================================================
# Valida se a stack Docker está operacional
# Uso: bash validate-install.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f .env ]; then
  echo "❌ Arquivo .env não encontrado."
  exit 1
fi

read_env_var() {
  grep -E "^${1}=" .env 2>/dev/null | head -1 | sed "s/^${1}=//" | tr -d '"' | tr -d "'"
}

KONG_PORT=$(read_env_var "KONG_HTTP_PORT")
KONG_PORT="${KONG_PORT:-8000}"
ANON_KEY=$(read_env_var "ANON_KEY")
SERVICE_ROLE_KEY=$(read_env_var "SERVICE_ROLE_KEY")

if [ -z "$ANON_KEY" ] || [ -z "$SERVICE_ROLE_KEY" ]; then
  echo "❌ ANON_KEY/SERVICE_ROLE_KEY não definidos no .env"
  exit 1
fi

POSTGRES_PASSWORD=$(read_env_var "POSTGRES_PASSWORD")
POSTGRES_DB=$(read_env_var "POSTGRES_DB")
POSTGRES_DB="${POSTGRES_DB:-simply_db}"

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

check_container() {
  local container="$1"
  local state restarting

  state=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || true)
  restarting=$(docker inspect -f '{{.State.Restarting}}' "$container" 2>/dev/null || true)

  if [ "$state" != "running" ] || [ "$restarting" = "true" ]; then
    echo "❌ Container $container não está saudável (status=$state, restarting=$restarting)."
    return 1
  fi

  echo "✅ $container está rodando"
}

echo "🔍 Validando containers..."
check_container simply-db
check_container simply-auth
check_container simply-rest
check_container simply-storage
check_container simply-functions
check_container simply-kong
check_container simply-frontend

AUTH_USERS_EXISTS=$(run_psql -tA -c "SELECT to_regclass('auth.users') IS NOT NULL;" | tr -d '[:space:]')
if [ "$AUTH_USERS_EXISTS" != "t" ]; then
  echo "❌ auth.users não existe (schema auth quebrado)."
  echo "💡 Execute: bash sync-db-passwords.sh && docker compose up -d --force-recreate auth kong"
  exit 1
fi

echo "✅ auth.users encontrado"
echo "🔍 Validando autenticação no Kong..."
AUTH_SERVICE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${KONG_PORT}/auth/v1/settings" -H "apikey: ${SERVICE_ROLE_KEY}" 2>/dev/null || echo "000")
AUTH_ANON_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${KONG_PORT}/auth/v1/settings" -H "apikey: ${ANON_KEY}" 2>/dev/null || echo "000")

if [ "$AUTH_SERVICE_STATUS" != "200" ] || [ "$AUTH_ANON_STATUS" != "200" ]; then
  echo "❌ Auth via Kong falhou (service=$AUTH_SERVICE_STATUS, anon=$AUTH_ANON_STATUS)."
  echo "💡 Execute: bash render-kong-config.sh && docker compose up -d --force-recreate kong"
  exit 1
fi

echo "✅ Auth via Kong respondeu HTTP 200 (anon e service)"

PASSWORD_STATUS=$(curl -s -o /tmp/simply_auth_password_check.json -w "%{http_code}" -X POST "http://localhost:${KONG_PORT}/auth/v1/token?grant_type=password" \
  -H "apikey: ${ANON_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"email":"healthcheck@simply.local","password":"invalid-password"}' 2>/dev/null || echo "000")

if [ "$PASSWORD_STATUS" -ge 500 ] 2>/dev/null || [ "$PASSWORD_STATUS" = "000" ]; then
  echo "❌ Fluxo de login por senha falhou (HTTP $PASSWORD_STATUS)."
  echo "📋 Resposta:"
  cat /tmp/simply_auth_password_check.json 2>/dev/null || true
  echo ""
  echo "💡 Execute: bash sync-db-passwords.sh && docker compose up -d --force-recreate auth kong"
  exit 1
fi

echo "✅ Fluxo de login por senha respondeu HTTP $PASSWORD_STATUS"

REST_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${KONG_PORT}/rest/v1/" \
  -H "apikey: ${SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" 2>/dev/null || echo "000")

if [ "$REST_STATUS" -ge 500 ] 2>/dev/null || [ "$REST_STATUS" = "000" ]; then
  echo "❌ /rest/v1/ retornou HTTP $REST_STATUS"
  exit 1
fi

echo "✅ REST respondeu HTTP $REST_STATUS"
echo "🎉 Validação concluída com sucesso."
