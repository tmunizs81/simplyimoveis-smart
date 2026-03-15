#!/bin/bash
# ============================================================
# Sincroniza senhas dos roles internos com POSTGRES_PASSWORD
# Uso: bash sync-db-passwords.sh [--quiet]
# ============================================================

set -euo pipefail

QUIET=false
if [ "${1:-}" = "--quiet" ]; then
  QUIET=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f .env ]; then
  echo "❌ Arquivo .env não encontrado em $SCRIPT_DIR"
  exit 1
fi

set -a
source .env
set +a

POSTGRES_DB="${POSTGRES_DB:-simply_db}"

if [ -z "${POSTGRES_PASSWORD:-}" ]; then
  echo "❌ POSTGRES_PASSWORD não definido no .env"
  exit 1
fi

log() {
  if [ "$QUIET" = false ]; then
    echo "$1"
  fi
}

log "🔧 Sincronizando credenciais internas do banco..."

docker compose up -d db >/dev/null

for _ in {1..30}; do
  DB_HEALTH=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' simply-db 2>/dev/null || true)
  if [ "$DB_HEALTH" = "healthy" ] || [ "$DB_HEALTH" = "running" ]; then
    break
  fi
  sleep 2
done

if [ "${DB_HEALTH:-}" != "healthy" ] && [ "${DB_HEALTH:-}" != "running" ]; then
  echo "❌ Banco não ficou pronto a tempo (estado: ${DB_HEALTH:-desconhecido})."
  exit 1
fi

docker compose exec -T db psql \
  -v ON_ERROR_STOP=1 \
  -U supabase_admin \
  -d "$POSTGRES_DB" \
  -v db_password="$POSTGRES_PASSWORD" <<'SQL'
ALTER ROLE supabase_admin WITH PASSWORD :'db_password';
ALTER ROLE supabase_auth_admin WITH PASSWORD :'db_password';
ALTER ROLE authenticator WITH PASSWORD :'db_password';
ALTER ROLE supabase_storage_admin WITH PASSWORD :'db_password';
SQL

log "✅ Senhas dos roles internos sincronizadas."
