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
# Usa PGPASSWORD para evitar prompt de senha
SQL_SYNC="ALTER ROLE supabase_admin WITH PASSWORD '${POSTGRES_PASSWORD}';
ALTER ROLE supabase_auth_admin WITH PASSWORD '${POSTGRES_PASSWORD}';
ALTER ROLE authenticator WITH PASSWORD '${POSTGRES_PASSWORD}';
ALTER ROLE supabase_storage_admin WITH PASSWORD '${POSTGRES_PASSWORD}';
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Corrige schema auth quebrado (erro 500: relation "users" does not exist)
DO \$\$
DECLARE
  r RECORD;
BEGIN
  IF to_regclass('auth.users') IS NULL THEN
    IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth') THEN
      EXECUTE 'DROP SCHEMA auth CASCADE';
    END IF;
    EXECUTE 'CREATE SCHEMA auth AUTHORIZATION supabase_auth_admin';
  END IF;

  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth') THEN
    -- Schema ownership
    EXECUTE 'ALTER SCHEMA auth OWNER TO supabase_auth_admin';

    -- Tabelas
    FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'auth' LOOP
      EXECUTE format('ALTER TABLE auth.%I OWNER TO supabase_auth_admin', r.tablename);
    END LOOP;

    -- Sequências
    FOR r IN SELECT sequence_name FROM information_schema.sequences WHERE sequence_schema = 'auth' LOOP
      EXECUTE format('ALTER SEQUENCE auth.%I OWNER TO supabase_auth_admin', r.sequence_name);
    END LOOP;

    -- Funções
    FOR r IN SELECT p.oid::regprocedure AS func_signature
             FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
             WHERE n.nspname = 'auth' LOOP
      EXECUTE format('ALTER FUNCTION %s OWNER TO supabase_auth_admin', r.func_signature);
    END LOOP;

    -- Views
    FOR r IN SELECT viewname FROM pg_views WHERE schemaname = 'auth' LOOP
      EXECUTE format('ALTER VIEW auth.%I OWNER TO supabase_auth_admin', r.viewname);
    END LOOP;

    -- Types
    FOR r IN SELECT t.typname
             FROM pg_type t JOIN pg_namespace n ON t.typnamespace = n.oid
             WHERE n.nspname = 'auth' AND t.typtype IN ('e','c') LOOP
      EXECUTE format('ALTER TYPE auth.%I OWNER TO supabase_auth_admin', r.typname);
    END LOOP;

    -- Grants
    EXECUTE 'GRANT USAGE ON SCHEMA auth TO supabase_auth_admin, authenticator, anon, authenticated, service_role';
    EXECUTE 'GRANT CREATE ON SCHEMA auth TO supabase_auth_admin';
    EXECUTE 'GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA auth TO supabase_auth_admin';
    EXECUTE 'GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA auth TO supabase_auth_admin';
    EXECUTE 'GRANT ALL PRIVILEGES ON ALL ROUTINES IN SCHEMA auth TO supabase_auth_admin';
    EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA auth GRANT ALL ON TABLES TO supabase_auth_admin';
    EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA auth GRANT ALL ON SEQUENCES TO supabase_auth_admin';
    EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA auth GRANT ALL ON ROUTINES TO supabase_auth_admin';

    -- Grants mínimos para authenticator (usado pelo PostgREST/GoTrue em runtime)
    EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA auth TO authenticator';
    EXECUTE 'GRANT USAGE ON ALL SEQUENCES IN SCHEMA auth TO authenticator';
  END IF;

  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'extensions') THEN
    EXECUTE 'GRANT USAGE ON SCHEMA extensions TO supabase_auth_admin, authenticator';
    EXECUTE 'GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA extensions TO supabase_auth_admin';
    EXECUTE 'GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA extensions TO supabase_auth_admin';
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
