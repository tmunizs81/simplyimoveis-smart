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

# Lê variáveis do .env de forma segura
POSTGRES_PASSWORD=$(grep -E '^POSTGRES_PASSWORD=' .env | head -1 | sed 's/^POSTGRES_PASSWORD=//' | tr -d '"' | tr -d "'")
POSTGRES_DB=$(grep -E '^POSTGRES_DB=' .env | head -1 | sed 's/^POSTGRES_DB=//' | tr -d '"' | tr -d "'")
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

docker compose up -d db >/dev/null 2>&1

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

# Usa PGPASSWORD para evitar prompt de senha
SQL_SYNC="ALTER ROLE supabase_admin WITH PASSWORD '${POSTGRES_PASSWORD}';
ALTER ROLE supabase_auth_admin WITH PASSWORD '${POSTGRES_PASSWORD}';
ALTER ROLE authenticator WITH PASSWORD '${POSTGRES_PASSWORD}';
ALTER ROLE supabase_storage_admin WITH PASSWORD '${POSTGRES_PASSWORD}';
CREATE EXTENSION IF NOT EXISTS pgcrypto;
DO \$\$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth') THEN
    EXECUTE 'GRANT USAGE ON SCHEMA auth TO supabase_auth_admin, authenticator, anon, authenticated, service_role';
    EXECUTE 'GRANT CREATE ON SCHEMA auth TO supabase_auth_admin';
    EXECUTE 'GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA auth TO supabase_auth_admin';
    EXECUTE 'GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA auth TO supabase_auth_admin';
    EXECUTE 'GRANT ALL PRIVILEGES ON ALL ROUTINES IN SCHEMA auth TO supabase_auth_admin';
    EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA auth GRANT ALL ON TABLES TO supabase_auth_admin';
    EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA auth GRANT ALL ON SEQUENCES TO supabase_auth_admin';
    EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA auth GRANT ALL ON ROUTINES TO supabase_auth_admin';
  END IF;

  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'extensions') THEN
    EXECUTE 'GRANT USAGE ON SCHEMA extensions TO supabase_auth_admin, authenticator';
  END IF;
END
\$\$;"

docker compose exec -T -e PGPASSWORD="${POSTGRES_PASSWORD}" db psql \
  -v ON_ERROR_STOP=1 \
  -U supabase_admin \
  -d "$POSTGRES_DB" \
  -c "$SQL_SYNC" 2>/dev/null || {
  # Fallback: tenta com usuário postgres (trust auth padrão)
  log "⚠️  Tentando com usuário postgres..."
  docker compose exec -T db psql \
    -v ON_ERROR_STOP=1 \
    -U postgres \
    -d "$POSTGRES_DB" \
    -c "$SQL_SYNC"
}

log "✅ Senhas dos roles internos sincronizadas."
