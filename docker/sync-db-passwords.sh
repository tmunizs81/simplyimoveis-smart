#!/bin/bash
# ============================================================
# Sincroniza (e repara) roles/senhas internos do banco
# Uso: bash sync-db-passwords.sh
# Versão: 2026-03-15-v12
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

[ ! -f .env ] && echo "❌ .env não encontrado" && exit 1

read_env() { grep -E "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"; }

POSTGRES_PASSWORD=$(read_env "POSTGRES_PASSWORD")
POSTGRES_DB=$(read_env "POSTGRES_DB")
POSTGRES_DB="${POSTGRES_DB:-simply_db}"
POSTGRES_USER_ENV=$(read_env "POSTGRES_USER")
DB_CONTAINER="simply-db"

[ -z "${POSTGRES_PASSWORD:-}" ] && echo "❌ POSTGRES_PASSWORD vazio" && exit 1

echo "🔧 Sincronizando credenciais..."

echo "   Verificando container ${DB_CONTAINER}..."
DB_STATUS=$(docker inspect -f '{{.State.Status}}' "$DB_CONTAINER" 2>/dev/null || echo "not_found")
if [ "$DB_STATUS" != "running" ]; then
  echo "❌ Container $DB_CONTAINER não está rodando (status: $DB_STATUS)"
  echo "   Rode: docker compose up -d db"
  exit 1
fi
echo "   ✅ Container rodando"

echo "   Procurando usuário administrativo válido..."
DB_ADMIN_USER=""
CANDIDATES=()
[ -n "${POSTGRES_USER_ENV:-}" ] && CANDIDATES+=("${POSTGRES_USER_ENV}")
CANDIDATES+=("supabase_admin" "postgres")

for i in {1..30}; do
  for candidate in "${CANDIDATES[@]}"; do
    [ -z "$candidate" ] && continue
    RESULT=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
      psql -tA -w -U "$candidate" -d "$POSTGRES_DB" -c "SELECT 1" 2>/dev/null || true)

    if [ "$RESULT" = "1" ]; then
      DB_ADMIN_USER="$candidate"
      echo "   ✅ Conexão SQL OK com usuário: $DB_ADMIN_USER"
      break 2
    fi
  done

  echo "   ⏳ tentativa $i/30..."
  sleep 2
done

if [ -z "$DB_ADMIN_USER" ]; then
  echo "❌ Não foi possível conectar ao PostgreSQL (usuarios tentados: ${CANDIDATES[*]})"
  docker logs --tail=50 "$DB_CONTAINER" || true
  exit 1
fi

echo "   Aplicando reparo de roles/senhas..."
ESCAPED_PASS=$(printf '%s' "$POSTGRES_PASSWORD" | sed "s/'/''/g")

docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
  psql -v ON_ERROR_STOP=1 -w -U "$DB_ADMIN_USER" -d "$POSTGRES_DB" <<EOSQL
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

DO $$
BEGIN
  EXECUTE format('ALTER DATABASE %I OWNER TO supabase_admin', current_database());
  EXECUTE format('GRANT CONNECT, TEMP ON DATABASE %I TO anon, authenticated, service_role, authenticator, supabase_auth_admin, supabase_storage_admin', current_database());
  EXECUTE format('GRANT CREATE ON DATABASE %I TO supabase_auth_admin, supabase_storage_admin', current_database());
  EXECUTE format('ALTER ROLE supabase_auth_admin IN DATABASE %I SET search_path = auth, public', current_database());
  EXECUTE format('ALTER ROLE supabase_storage_admin IN DATABASE %I SET search_path = storage, public', current_database());
  EXECUTE format('ALTER ROLE authenticator IN DATABASE %I SET search_path = public, auth, storage', current_database());
END $$;

CREATE SCHEMA IF NOT EXISTS auth AUTHORIZATION supabase_auth_admin;
ALTER SCHEMA auth OWNER TO supabase_auth_admin;
CREATE SCHEMA IF NOT EXISTS storage AUTHORIZATION supabase_storage_admin;
ALTER SCHEMA storage OWNER TO supabase_storage_admin;

CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION auth.role()
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('request.jwt.claim.role', true), '')::text;
$$;

CREATE OR REPLACE FUNCTION auth.email()
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('request.jwt.claim.email', true), '')::text;
$$;

GRANT USAGE ON SCHEMA auth TO supabase_auth_admin, authenticator, anon, authenticated, service_role;
GRANT CREATE ON SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON ALL TABLES IN SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON ALL ROUTINES IN SCHEMA auth TO supabase_auth_admin;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated, service_role, authenticator;
GRANT EXECUTE ON FUNCTION auth.role() TO anon, authenticated, service_role, authenticator;
GRANT EXECUTE ON FUNCTION auth.email() TO anon, authenticated, service_role, authenticator;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON TABLES TO supabase_auth_admin;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON SEQUENCES TO supabase_auth_admin;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON ROUTINES TO supabase_auth_admin;

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role, authenticator;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;
EOSQL

echo "✅ Credenciais sincronizadas com sucesso!"