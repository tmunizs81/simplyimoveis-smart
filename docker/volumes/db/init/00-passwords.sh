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

# Run each critical command individually to avoid heredoc escaping issues
run_sql() {
  psql -v ON_ERROR_STOP=1 --username "$DB_USER" --dbname "$DB_NAME" -c "$1"
}

# Create roles
for role_sql in \
  "DO \$b\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='postgres') THEN CREATE ROLE postgres WITH LOGIN SUPERUSER CREATEDB CREATEROLE REPLICATION BYPASSRLS; END IF; END \$b\$;" \
  "DO \$b\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='supabase_admin') THEN CREATE ROLE supabase_admin WITH LOGIN SUPERUSER CREATEDB CREATEROLE REPLICATION BYPASSRLS; END IF; END \$b\$;" \
  "DO \$b\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='supabase_auth_admin') THEN CREATE ROLE supabase_auth_admin WITH LOGIN NOINHERIT CREATEROLE CREATEDB; END IF; END \$b\$;" \
  "DO \$b\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='supabase_storage_admin') THEN CREATE ROLE supabase_storage_admin WITH LOGIN NOINHERIT CREATEROLE CREATEDB; END IF; END \$b\$;" \
  "DO \$b\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticator') THEN CREATE ROLE authenticator WITH LOGIN NOINHERIT; END IF; END \$b\$;" \
  "DO \$b\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN NOINHERIT; END IF; END \$b\$;" \
  "DO \$b\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN NOINHERIT; END IF; END \$b\$;" \
  "DO \$b\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS; END IF; END \$b\$;" \
; do
  run_sql "$role_sql"
done

# Set passwords
run_sql "ALTER ROLE postgres WITH PASSWORD '${ESCAPED_PASS}';"
run_sql "ALTER ROLE supabase_admin WITH PASSWORD '${ESCAPED_PASS}';"
run_sql "ALTER ROLE supabase_auth_admin WITH PASSWORD '${ESCAPED_PASS}';"
run_sql "ALTER ROLE supabase_storage_admin WITH PASSWORD '${ESCAPED_PASS}';"
run_sql "ALTER ROLE authenticator WITH PASSWORD '${ESCAPED_PASS}';"

# Grant roles
run_sql "GRANT anon TO authenticator;"
run_sql "GRANT authenticated TO authenticator;"
run_sql "GRANT service_role TO authenticator;"

# Database ownership and permissions
run_sql "ALTER DATABASE \"${DB_NAME}\" OWNER TO supabase_admin;"
run_sql "GRANT CONNECT, TEMP ON DATABASE \"${DB_NAME}\" TO anon, authenticated, service_role, authenticator, supabase_auth_admin, supabase_storage_admin;"
run_sql "GRANT CREATE ON DATABASE \"${DB_NAME}\" TO supabase_auth_admin, supabase_storage_admin;"

# Search paths
run_sql "ALTER ROLE supabase_auth_admin SET search_path = auth, public;"
run_sql "ALTER ROLE supabase_storage_admin SET search_path = storage, public;"
run_sql "ALTER ROLE authenticator SET search_path = public, auth, storage;"
run_sql "ALTER ROLE supabase_auth_admin IN DATABASE \"${DB_NAME}\" SET search_path = auth, public;"
run_sql "ALTER ROLE supabase_storage_admin IN DATABASE \"${DB_NAME}\" SET search_path = storage, public;"
run_sql "ALTER ROLE authenticator IN DATABASE \"${DB_NAME}\" SET search_path = public, auth, storage;"

# Create schemas
run_sql "CREATE SCHEMA IF NOT EXISTS auth AUTHORIZATION supabase_auth_admin;"
run_sql "ALTER SCHEMA auth OWNER TO supabase_auth_admin;"
run_sql "CREATE SCHEMA IF NOT EXISTS storage AUTHORIZATION supabase_storage_admin;"
run_sql "ALTER SCHEMA storage OWNER TO supabase_storage_admin;"

# Create auth functions using quoted heredoc (no shell expansion needed)
psql -v ON_ERROR_STOP=1 --username "$DB_USER" --dbname "$DB_NAME" <<'EOSQL'
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
EOSQL

# Auth schema grants
run_sql "GRANT USAGE ON SCHEMA auth TO supabase_auth_admin, authenticator, anon, authenticated, service_role;"
run_sql "GRANT CREATE ON SCHEMA auth TO supabase_auth_admin;"
run_sql "GRANT ALL ON ALL TABLES IN SCHEMA auth TO supabase_auth_admin;"
run_sql "GRANT ALL ON ALL SEQUENCES IN SCHEMA auth TO supabase_auth_admin;"
run_sql "GRANT ALL ON ALL ROUTINES IN SCHEMA auth TO supabase_auth_admin;"
run_sql "GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated, service_role, authenticator;"
run_sql "GRANT EXECUTE ON FUNCTION auth.role() TO anon, authenticated, service_role, authenticator;"
run_sql "GRANT EXECUTE ON FUNCTION auth.email() TO anon, authenticated, service_role, authenticator;"
run_sql "ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON TABLES TO supabase_auth_admin;"
run_sql "ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON SEQUENCES TO supabase_auth_admin;"
run_sql "ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON ROUTINES TO supabase_auth_admin;"

# Storage schema grants
run_sql "GRANT USAGE, CREATE ON SCHEMA storage TO supabase_storage_admin;"
run_sql "GRANT ALL ON ALL TABLES IN SCHEMA storage TO supabase_storage_admin;"
run_sql "GRANT ALL ON ALL SEQUENCES IN SCHEMA storage TO supabase_storage_admin;"
run_sql "GRANT ALL ON ALL ROUTINES IN SCHEMA storage TO supabase_storage_admin;"
run_sql "GRANT USAGE ON SCHEMA storage TO authenticator, service_role;"

# Public schema grants
run_sql "GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role, authenticator;"
run_sql "GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;"
run_sql "GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;"
run_sql "GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO anon, authenticated, service_role;"
run_sql "ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;"
run_sql "ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;"
run_sql "ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;"

run_sql "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
run_sql "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";"

echo "✅ Roles e senhas internas configurados!"
