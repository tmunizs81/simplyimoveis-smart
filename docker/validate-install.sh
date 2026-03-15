#!/bin/bash
# ============================================================
# Valida stack Docker — retorna 0 se OK, 1 se problemas
# Versão: 2026-03-15-v12-selfhosted-hardening
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
DB_USER=$(read_env "POSTGRES_USER"); DB_USER="${DB_USER:-supabase_admin}"

[ -z "$ANON_KEY" ] || [ -z "$SERVICE_ROLE_KEY" ] && echo "❌ Chaves JWT não definidas" && exit 1

ERRORS=0

echo "── Containers ──"
for c in simply-db simply-auth simply-rest simply-storage simply-functions simply-kong simply-frontend; do
  st=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo "missing")
  rs=$(docker inspect -f '{{.State.Restarting}}' "$c" 2>/dev/null || echo "false")
  if [ "$st" != "running" ] || [ "$rs" = "true" ]; then
    echo "❌ $c ($st)"; ERRORS=$((ERRORS+1))
  else
    echo "✅ $c"
  fi
done

echo "── Auth ──"
AUTH_ST=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${KONG_PORT}/auth/v1/settings" -H "apikey: ${ANON_KEY}" 2>/dev/null || echo "000")
if [ "$AUTH_ST" != "200" ]; then
  echo "❌ Auth: HTTP $AUTH_ST"; ERRORS=$((ERRORS+1))
else
  echo "✅ Auth: OK"
fi

echo "── REST ──"
REST_ST=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${KONG_PORT}/rest/v1/" \
  -H "apikey: ${SERVICE_ROLE_KEY}" -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" 2>/dev/null || echo "000")
if [ "$REST_ST" -ge 500 ] 2>/dev/null || [ "$REST_ST" = "000" ]; then
  echo "❌ REST: HTTP $REST_ST"; ERRORS=$((ERRORS+1))
else
  echo "✅ REST: OK"
fi

echo "── Functions (arquivos) ──"
FUNC_DIR="volumes/functions"
for fn in chat create-admin-user notify-telegram admin-crud; do
  fn_file="$FUNC_DIR/$fn/index.ts"
  if [ ! -f "$fn_file" ]; then
    echo "❌ $fn: arquivo ausente ($fn_file)"; ERRORS=$((ERRORS+1))
  elif ! grep -qE '^\s*export\s+default\s' "$fn_file"; then
    echo "❌ $fn: falta 'export default handler' — o runtime vai crashar"
    echo "   💡 Adicione ao final do arquivo: export default handler;"
    ERRORS=$((ERRORS+1))
  else
    echo "✅ $fn: export default OK"
  fi
done

if [ ! -f "$FUNC_DIR/main/index.ts" ]; then
  echo "❌ main router ausente: $FUNC_DIR/main/index.ts"
  ERRORS=$((ERRORS+1))
else
  echo "✅ main router presente"
fi

echo "── Functions (runtime) ──"
FUNC_LOGS=$(docker logs simply-functions --tail=80 2>&1 || true)
if echo "$FUNC_LOGS" | grep -Eqi "main worker boot error|worker boot error|boot error"; then
  echo "❌ Functions runtime: boot error detectado"
  echo "   $(echo "$FUNC_LOGS" | grep -Ei 'main worker boot error|worker boot error|boot error' | head -1)"
  ERRORS=$((ERRORS+1))
else
  # admin-crud sem token deve retornar 401 (se runtime estiver saudável)
  CRUD_ST=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://localhost:${KONG_PORT}/functions/v1/admin-crud" \
    -H "apikey: ${ANON_KEY}" -H "Content-Type: application/json" -d '{"action":"select","table":"properties"}' 2>/dev/null || echo "000")

  # create-admin-user sem token também deve retornar 401
  USER_ST=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://localhost:${KONG_PORT}/functions/v1/create-admin-user" \
    -H "apikey: ${ANON_KEY}" -H "Content-Type: application/json" -d '{"action":"list"}' 2>/dev/null || echo "000")

  if [ "$CRUD_ST" = "401" ] || [ "$CRUD_ST" = "403" ]; then
    echo "✅ admin-crud: HTTP $CRUD_ST (runtime ativo)"
  else
    echo "❌ admin-crud: HTTP $CRUD_ST"
    ERRORS=$((ERRORS+1))
  fi

  if [ "$USER_ST" = "401" ] || [ "$USER_ST" = "403" ]; then
    echo "✅ create-admin-user: HTTP $USER_ST (runtime ativo)"
  else
    echo "❌ create-admin-user: HTTP $USER_ST"
    ERRORS=$((ERRORS+1))
  fi
fi

echo ""
if [ "$ERRORS" -gt 0 ]; then
  echo "❌ $ERRORS problema(s). Debug: docker compose logs --tail=80"
  exit 1
fi
echo "🎉 Tudo OK!"
