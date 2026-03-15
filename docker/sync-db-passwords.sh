#!/bin/bash
# ============================================================
# Sincroniza senhas dos roles internos do Supabase
# Uso: bash sync-db-passwords.sh [--quiet]
# Versão: 2026-03-15-v5-rewrite
# ============================================================

set -euo pipefail

QUIET=false
[ "${1:-}" = "--quiet" ] && QUIET=true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

[ ! -f .env ] && echo "❌ .env não encontrado" && exit 1

POSTGRES_PASSWORD=$(grep -E '^POSTGRES_PASSWORD=' .env | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
POSTGRES_DB=$(grep -E '^POSTGRES_DB=' .env | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
POSTGRES_DB="${POSTGRES_DB:-simply_db}"

[ -z "${POSTGRES_PASSWORD:-}" ] && echo "❌ POSTGRES_PASSWORD vazio" && exit 1

log() { [ "$QUIET" = false ] && echo "$1"; }

# Espera banco ficar pronto
wait_db() {
  docker compose up -d db >/dev/null 2>&1
  for _ in {1..30}; do
    if docker compose exec -T db pg_isready -U postgres -q 2>/dev/null; then
      return 0
    fi
    sleep 2
  done
  echo "❌ Banco não ficou pronto." && exit 1
}

# Executa SQL sempre como postgres (superuser, sem senha dentro do container)
run_sql() {
  docker compose exec -T db psql -v ON_ERROR_STOP=1 -U postgres -d "$POSTGRES_DB" "$@"
}

log "🔧 Sincronizando credenciais..."
wait_db

run_sql <<EOSQL
-- 1) Senhas dos roles internos
ALTER ROLE supabase_admin WITH PASSWORD '${POSTGRES_PASSWORD}';
ALTER ROLE supabase_auth_admin WITH PASSWORD '${POSTGRES_PASSWORD}';
ALTER ROLE authenticator WITH PASSWORD '${POSTGRES_PASSWORD}';
ALTER ROLE supabase_storage_admin WITH PASSWORD '${POSTGRES_PASSWORD}';

-- 2) Extensão pgcrypto
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 3) Garante schema auth existe com owner correto
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth') THEN
    CREATE SCHEMA auth AUTHORIZATION supabase_auth_admin;
  ELSE
    ALTER SCHEMA auth OWNER TO supabase_auth_admin;
  END IF;
END \$\$;

-- 4) Ownership de objetos existentes no schema auth (tabelas, sequências, funções, views)
DO \$\$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'auth' LOOP
    EXECUTE format('ALTER TABLE auth.%I OWNER TO supabase_auth_admin', r.tablename);
  END LOOP;

  FOR r IN SELECT sequence_name FROM information_schema.sequences WHERE sequence_schema = 'auth' LOOP
    EXECUTE format('ALTER SEQUENCE auth.%I OWNER TO supabase_auth_admin', r.sequence_name);
  END LOOP;

  FOR r IN SELECT p.oid::regprocedure AS sig FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE n.nspname = 'auth' LOOP
    EXECUTE format('ALTER FUNCTION %s OWNER TO supabase_auth_admin', r.sig);
  END LOOP;

  FOR r IN SELECT viewname FROM pg_views WHERE schemaname = 'auth' LOOP
    EXECUTE format('ALTER VIEW auth.%I OWNER TO supabase_auth_admin', r.viewname);
  END LOOP;

  -- Enums apenas (typtype='e'), NUNCA row types (typrelid>0)
  FOR r IN SELECT t.typname FROM pg_type t JOIN pg_namespace n ON t.typnamespace = n.oid
           WHERE n.nspname = 'auth' AND t.typtype = 'e' AND t.typrelid = 0 LOOP
    EXECUTE format('ALTER TYPE auth.%I OWNER TO supabase_auth_admin', r.typname);
  END LOOP;
END \$\$;

-- 5) Grants
GRANT USAGE ON SCHEMA auth TO supabase_auth_admin, authenticator, anon, authenticated, service_role;
GRANT CREATE ON SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON ALL TABLES IN SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON ALL ROUTINES IN SCHEMA auth TO supabase_auth_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA auth TO authenticator;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA auth TO authenticator;

-- Extensions schema (se existir)
DO \$\$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'extensions') THEN
    GRANT USAGE ON SCHEMA extensions TO supabase_auth_admin, authenticator;
    GRANT ALL ON ALL TABLES IN SCHEMA extensions TO supabase_auth_admin;
  END IF;
END \$\$;
EOSQL

log "✅ Credenciais sincronizadas."
