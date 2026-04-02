#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

[ -f "$ENV_FILE" ] || { echo "❌ .env não encontrado em $ENV_FILE"; exit 1; }

read_env() {
  grep -E "^${1}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"
}

compose() {
  docker compose -f "$COMPOSE_FILE" --project-directory "$SCRIPT_DIR" "$@"
}

run_sql() {
  compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" db \
    psql -P pager=off -w -h 127.0.0.1 -U "$DB_USER" -d "$POSTGRES_DB" -c "$1"
}

KONG_PORT="$(read_env "KONG_HTTP_PORT")"; KONG_PORT="${KONG_PORT:-8000}"
ANON_KEY="$(read_env "ANON_KEY")"
SERVICE_ROLE_KEY="$(read_env "SERVICE_ROLE_KEY")"
POSTGRES_PASSWORD="$(read_env "POSTGRES_PASSWORD")"
POSTGRES_DB="$(read_env "POSTGRES_DB")"; POSTGRES_DB="${POSTGRES_DB:-simply_db}"
DB_USER="$(read_env "POSTGRES_USER")"; DB_USER="${DB_USER:-supabase_admin}"
ADMIN_EMAIL="${1:-$(read_env "ADMIN_EMAIL")}"
ADMIN_PASSWORD="${2:-$(read_env "ADMIN_PASSWORD")}"
DEBUG_PATH="__debug__/storage-upload-$(date +%s).txt"
DEBUG_PAYLOAD="debug-storage $(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "══════════════════════════════════════════════════"
echo "  Debug Storage Upload (self-hosted)"
echo "══════════════════════════════════════════════════"

echo
echo "1) Roles e memberships"
run_sql "
SELECT rolname, rolinherit, rolbypassrls
FROM pg_roles
WHERE rolname IN ('authenticator','service_role','supabase_storage_admin','authenticated','anon')
ORDER BY rolname;"

run_sql "
SELECT
  pg_has_role('authenticator', 'service_role', 'MEMBER') AS authenticator_service_role,
  pg_has_role('supabase_storage_admin', 'service_role', 'MEMBER') AS storage_admin_service_role,
  pg_has_role('supabase_storage_admin', 'authenticated', 'MEMBER') AS storage_admin_authenticated;"

echo
echo "2) Grants e policies do storage"
run_sql "
SELECT table_schema, table_name, privilege_type, grantee
FROM information_schema.role_table_grants
WHERE table_schema = 'storage'
  AND table_name IN ('objects','buckets')
  AND grantee IN ('anon','authenticated','service_role','supabase_storage_admin')
ORDER BY table_name, grantee, privilege_type;"

run_sql "
SELECT policyname, roles, cmd
FROM pg_policies
WHERE schemaname = 'storage' AND tablename = 'objects'
ORDER BY policyname;"

echo
echo "3) Smoke via /storage/v1 com SERVICE_ROLE_KEY"
SERVICE_HTTP=$(printf "%s" "$DEBUG_PAYLOAD" | curl -sS -m 20 -o /tmp/debug-storage-service.json -w "%{http_code}" \
  -X POST "http://127.0.0.1:${KONG_PORT}/storage/v1/object/property-media/${DEBUG_PATH}" \
  -H "apikey: ${SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" \
  -H "Content-Type: text/plain" \
  -H "x-upsert: true" \
  --data-binary @- 2>/dev/null || echo "000")
echo "HTTP: $SERVICE_HTTP"
cat /tmp/debug-storage-service.json 2>/dev/null || true
echo

if [ -n "$ADMIN_EMAIL" ] && [ -n "$ADMIN_PASSWORD" ]; then
  echo
  echo "4) Smoke real via admin-crud com JWT do admin"
  ADMIN_LOGIN_BODY=$(python3 - "$ADMIN_EMAIL" "$ADMIN_PASSWORD" <<'PY'
import json
import sys

print(json.dumps({"email": sys.argv[1], "password": sys.argv[2]}))
PY
)

  ADMIN_TOKEN=$(curl -sS -m 15 -X POST "http://127.0.0.1:${KONG_PORT}/auth/v1/token?grant_type=password" \
    -H "apikey: ${ANON_KEY}" \
    -H "Content-Type: application/json" \
    -d "$ADMIN_LOGIN_BODY" 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || true)

  if [ -n "$ADMIN_TOKEN" ]; then
    ADMIN_HTTP=$(printf "%s" "$DEBUG_PAYLOAD" | curl -sS -m 20 -o /tmp/debug-storage-admin-crud.json -w "%{http_code}" \
      -X POST "http://127.0.0.1:${KONG_PORT}/functions/v1/admin-crud?storage_action=upload&bucket=property-media&path=${DEBUG_PATH}" \
      -H "apikey: ${ANON_KEY}" \
      -H "Authorization: Bearer ${ADMIN_TOKEN}" \
      -H "Content-Type: text/plain" \
      --data-binary @- 2>/dev/null || echo "000")
    echo "HTTP: $ADMIN_HTTP"
    cat /tmp/debug-storage-admin-crud.json 2>/dev/null || true
    echo
  else
    echo "⚠️ Não foi possível obter o token do admin."
  fi
else
  echo
  echo "4) Smoke real via admin-crud com JWT do admin"
  echo "⚠️ Informe email/senha: bash debug-storage-upload.sh admin@dominio.com senha"
fi

echo
echo "5) Logs recentes"
compose logs --tail=120 storage rest kong functions || true