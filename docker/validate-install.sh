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

set -a
source .env
set +a

KONG_PORT="${KONG_HTTP_PORT:-8000}"
API_KEY="${SERVICE_ROLE_KEY:-${ANON_KEY:-}}"

if [ -z "$API_KEY" ]; then
  echo "❌ SERVICE_ROLE_KEY/ANON_KEY não definidos no .env"
  exit 1
fi

check_container() {
  local container="$1"
  local state
  local restarting

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

echo "🔍 Validando endpoints..."
AUTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${KONG_PORT}/auth/v1/settings" \
  -H "apikey: ${API_KEY}")

if [ "$AUTH_STATUS" != "200" ]; then
  echo "❌ /auth/v1/settings retornou HTTP $AUTH_STATUS"
  exit 1
fi

echo "✅ Auth respondeu HTTP 200"

REST_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${KONG_PORT}/rest/v1/" \
  -H "apikey: ${API_KEY}" \
  -H "Authorization: Bearer ${API_KEY}")

if [ "$REST_STATUS" -ge 500 ] || [ "$REST_STATUS" = "000" ]; then
  echo "❌ /rest/v1/ retornou HTTP $REST_STATUS"
  exit 1
fi

echo "✅ REST respondeu HTTP $REST_STATUS"

echo "🎉 Validação concluída com sucesso."
