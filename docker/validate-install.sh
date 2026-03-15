#!/bin/bash
# ============================================================
# Valida stack Docker — retorna 0 se tudo OK, 1 se problemas
# Versão: 2026-03-15-v9
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

[ ! -f .env ] && echo "❌ .env não encontrado" && exit 1

read_env() { grep -E "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"; }

KONG_PORT=$(read_env "KONG_HTTP_PORT"); KONG_PORT="${KONG_PORT:-8000}"
ANON_KEY=$(read_env "ANON_KEY")
SERVICE_ROLE_KEY=$(read_env "SERVICE_ROLE_KEY")
POSTGRES_DB=$(read_env "POSTGRES_DB"); POSTGRES_DB="${POSTGRES_DB:-simply_db}"
POSTGRES_PASSWORD=$(read_env "POSTGRES_PASSWORD")

[ -z "$ANON_KEY" ] || [ -z "$SERVICE_ROLE_KEY" ] && echo "❌ Chaves JWT não definidas" && exit 1

ERRORS=0

check_container() {
  local c="$1"
  local st=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo "missing")
  local rs=$(docker inspect -f '{{.State.Restarting}}' "$c" 2>/dev/null || echo "false")
  if [ "$st" != "running" ] || [ "$rs" = "true" ]; then
    echo "❌ $c ($st, restarting=$rs)"; ERRORS=$((ERRORS+1)); return 1
  fi
  echo "✅ $c"
}

echo "── Containers ──"
for c in simply-db simply-auth simply-rest simply-storage simply-functions simply-kong simply-frontend; do
  check_container "$c" || true
done

echo "── Schema auth ──"
AUTH_OK=$(docker compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" db \
  psql -tA -w -U postgres -d "$POSTGRES_DB" \
  -c "SELECT to_regclass('auth.users') IS NOT NULL;" 2>/dev/null | tr -d '[:space:]')
if [ "$AUTH_OK" != "t" ]; then
  echo "❌ auth.users não existe"; ERRORS=$((ERRORS+1))
else
  echo "✅ auth.users"
fi

echo "── API ──"
AUTH_ST=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${KONG_PORT}/auth/v1/settings" \
  -H "apikey: ${ANON_KEY}" 2>/dev/null || echo "000")
if [ "$AUTH_ST" != "200" ]; then
  echo "❌ Auth settings: HTTP $AUTH_ST"; ERRORS=$((ERRORS+1))
else
  echo "✅ Auth settings: 200"
fi

LOGIN_ST=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  "http://localhost:${KONG_PORT}/auth/v1/token?grant_type=password" \
  -H "apikey: ${ANON_KEY}" -H "Content-Type: application/json" \
  -d '{"email":"test@invalid.local","password":"wrong"}' 2>/dev/null || echo "000")
if [ "$LOGIN_ST" -ge 500 ] 2>/dev/null || [ "$LOGIN_ST" = "000" ]; then
  echo "❌ Login flow: HTTP $LOGIN_ST (esperava 400)"; ERRORS=$((ERRORS+1))
else
  echo "✅ Login flow: HTTP $LOGIN_ST"
fi

REST_ST=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${KONG_PORT}/rest/v1/" \
  -H "apikey: ${SERVICE_ROLE_KEY}" -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" 2>/dev/null || echo "000")
if [ "$REST_ST" -ge 500 ] 2>/dev/null || [ "$REST_ST" = "000" ]; then
  echo "❌ REST: HTTP $REST_ST"; ERRORS=$((ERRORS+1))
else
  echo "✅ REST: HTTP $REST_ST"
fi

echo ""
[ "$ERRORS" -gt 0 ] && echo "❌ $ERRORS problema(s)" && exit 1
echo "🎉 Tudo OK!"
