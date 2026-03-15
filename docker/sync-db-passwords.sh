#!/bin/bash
# ============================================================
# Sincroniza senhas e permissões dos roles internos do Supabase
# Corrige ownership do schema auth (causa raiz do erro 500)
# Uso: bash sync-db-passwords.sh [--quiet]
# Versão: 2026-03-15-v3
# ============================================================

set -euo pipefail

QUIET=false
[ "${1:-}" = "--quiet" ] && QUIET=true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

[ ! -f .env ] && echo "❌ .env não encontrado em $SCRIPT_DIR" && exit 1

POSTGRES_PASSWORD=$(grep -E '^POSTGRES_PASSWORD=' .env | head -1 | sed 's/^POSTGRES_PASSWORD=//' | tr -d '"' | tr -d "'")
POSTGRES_DB=$(grep -E '^POSTGRES_DB=' .env | head -1 | sed 's/^POSTGRES_DB=//' | tr -d '"' | tr -d "'")
POSTGRES_DB="${POSTGRES_DB:-simply_db}"

[ -z "${POSTGRES_PASSWORD:-}" ] && echo "❌ POSTGRES_PASSWORD não definido" && exit 1

log() { [ "$QUIET" = false ] && echo "$1"; }

log "🔧 Sincronizando credenciais e permissões..."

docker compose up -d db >/dev/null 2>&1

for _ in {1..30}; do
  DB_HEALTH=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' simply-db 2>/dev/null || true)
  [ "$DB_HEALTH" = "healthy" ] || [ "$DB_HEALTH" = "running" ] && break
  sleep 2
done

[ "${DB_HEALTH:-}" != "healthy" ] && [ "${DB_HEALTH:-}" != "running" ] && echo "❌ Banco não ficou pronto." && exit 1

# Monta SQL num arquivo temporário para evitar problemas de escape
TMP_SQL=$(mktemp /tmp/sync-db-XXXXXX.sql)
cat > "$TMP_SQL" << 'EOSQL'
-- Senhas dos roles internos
DO $$
BEGIN
  EXECUTE format('ALTER ROLE supabase_admin WITH PASSWORD %L', current_setting('app.pg_pass'));
  EXECUTE format('ALTER ROLE supabase_auth_admin WITH PASSWORD %L', current_setting('app.pg_pass'));
  EXECUTE format('ALTER ROLE authenticator WITH PASSWORD %L', current_setting('app.pg_pass'));
  EXECUTE format('ALTER ROLE supabase_storage_admin WITH PASSWORD %L', current_setting('app.pg_pass'));
END $$;

-- Extensões necessárias
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Corrige schema auth (ownership + grants)
DO $$
DECLARE
  r RECORD;
BEGIN
  -- Se auth.users não existe, recria schema para GoTrue migrar do zero
  IF to_regclass('auth.users') IS NULL THEN
    IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth') THEN
      EXECUTE 'DROP SCHEMA auth CASCADE';
    END IF;
    EXECUTE 'CREATE SCHEMA auth AUTHORIZATION supabase_auth_admin';
    RAISE NOTICE 'Schema auth recriado do zero (GoTrue irá migrar ao subir)';
    RETURN;
  END IF;

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
  FOR r IN SELECT p.oid::regprocedure AS func_sig
           FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
           WHERE n.nspname = 'auth' LOOP
    EXECUTE format('ALTER FUNCTION %s OWNER TO supabase_auth_admin', r.func_sig);
  END LOOP;

  -- Views
  FOR r IN SELECT viewname FROM pg_views WHERE schemaname = 'auth' LOOP
    EXECUTE format('ALTER VIEW auth.%I OWNER TO supabase_auth_admin', r.viewname);
  END LOOP;

  -- Types (EXCLUIR row types de tabelas e composite types internos)
  FOR r IN SELECT t.typname
           FROM pg_type t
           JOIN pg_namespace n ON t.typnamespace = n.oid
           WHERE n.nspname = 'auth'
             AND t.typtype = 'e'  -- apenas enums
  LOOP
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

  -- Grants para authenticator (runtime GoTrue)
  EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA auth TO authenticator';
  EXECUTE 'GRANT USAGE ON ALL SEQUENCES IN SCHEMA auth TO authenticator';

  -- Extensions schema
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'extensions') THEN
    EXECUTE 'GRANT USAGE ON SCHEMA extensions TO supabase_auth_admin, authenticator';
    EXECUTE 'GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA extensions TO supabase_auth_admin';
    EXECUTE 'GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA extensions TO supabase_auth_admin';
  END IF;
END $$;
EOSQL

docker compose exec -T \
  -e PGPASSWORD="${POSTGRES_PASSWORD}" \
  -e PGOPTIONS="-c app.pg_pass=${POSTGRES_PASSWORD}" \
  db psql -v ON_ERROR_STOP=1 -U supabase_admin -d "$POSTGRES_DB" -f - < "$TMP_SQL" 2>/dev/null || {
  log "⚠️  Tentando com usuário postgres..."
  docker compose exec -T \
    -e PGOPTIONS="-c app.pg_pass=${POSTGRES_PASSWORD}" \
    db psql -v ON_ERROR_STOP=1 -U postgres -d "$POSTGRES_DB" -f - < "$TMP_SQL"
}

rm -f "$TMP_SQL"
log "✅ Credenciais e permissões sincronizadas."