#!/bin/bash
# ============================================================
# Define/normaliza roles internos e senhas no bootstrap do banco
# ============================================================
set -euo pipefail

echo "🔐 Configurando roles e senhas internas..."

DB_NAME="${POSTGRES_DB:-simply_db}"
ESCAPED_PASS=$(printf '%s' "${POSTGRES_PASSWORD:-}" | sed "s/'/''/g")

if [ -z "${ESCAPED_PASS}" ]; then
  echo "❌ POSTGRES_PASSWORD vazio durante bootstrap"
  exit 1
fi

DB_USER=""
CANDIDATES=()
[ -n "${POSTGRES_USER:-}" ] && CANDIDATES+=("${POSTGRES_USER}")
CANDIDATES+=("supabase_admin" "postgres")

for candidate in "${CANDIDATES[@]}"; do
  [ -z "$candidate" ] && continue
  if psql --username "$candidate" --dbname "$DB_NAME" -tA -c "SELECT 1" >/dev/null 2>&1; then
    DB_USER="$candidate"
    break
  fi
done

if [ -z "$DB_USER" ]; then
  echo "❌ Não consegui conectar no bootstrap com supabase_admin/postgres"
  exit 1
fi

echo "   ✅ Conectado como $DB_USER"

psql -v ON_ERROR_STOP=1 --username "$DB_USER" --dbname "$DB_NAME" <<EOSQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'postgres') THEN
    CREATE ROLE postgres WITH LOGIN SUPERUSER CREATEDB CREATEROLE REPLICATION BYPASSRLS;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_admin') THEN
    CREATE ROLE supabase_admin WITH LOGIN SUPERUSER CREATEDB CREATEROLE REPLICATION BYPASSRLS;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
    CREATE ROLE supabase_auth_admin WITH LOGIN NOINHERIT CREATEROLE CREATEDB;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_storage_admin') THEN
    CREATE ROLE supabase_storage_admin WITH LOGIN NOINHERIT CREATEROLE CREATEDB;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticator') THEN
    CREATE ROLE authenticator WITH LOGIN NOINHERIT;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN NOINHERIT;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN NOINHERIT;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
  END IF;
END \$\$;

ALTER ROLE postgres WITH PASSWORD '${ESCAPED_PASS}';
ALTER ROLE supabase_admin WITH PASSWORD '${ESCAPED_PASS}';
ALTER ROLE supabase_auth_admin WITH PASSWORD '${ESCAPED_PASS}';
ALTER ROLE supabase_storage_admin WITH PASSWORD '${ESCAPED_PASS}';
ALTER ROLE authenticator WITH PASSWORD '${ESCAPED_PASS}';

GRANT anon TO authenticator;
GRANT authenticated TO authenticator;
GRANT service_role TO authenticator;

CREATE SCHEMA IF NOT EXISTS auth AUTHORIZATION supabase_auth_admin;
ALTER SCHEMA auth OWNER TO supabase_auth_admin;

GRANT USAGE ON SCHEMA auth TO supabase_auth_admin, authenticator, anon, authenticated, service_role;
GRANT CREATE ON SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON ALL TABLES IN SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON ALL ROUTINES IN SCHEMA auth TO supabase_auth_admin;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON TABLES TO supabase_auth_admin;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON SEQUENCES TO supabase_auth_admin;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON ROUTINES TO supabase_auth_admin;

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role, authenticator;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
EOSQL

echo "✅ Roles e senhas internas configurados!"