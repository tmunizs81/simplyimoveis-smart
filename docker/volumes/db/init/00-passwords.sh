#!/bin/bash
# ============================================================
# Bootstrap: cria roles, senhas, schemas, funções auth, grants
# Executa UMA VEZ no primeiro start do container db
# Versão: 2026-03-15-v11-simplified
# ============================================================
set -euo pipefail

echo "🔐 Bootstrap: configurando roles e permissões..."

DB_NAME="${POSTGRES_DB:-simply_db}"
PASS="${POSTGRES_PASSWORD:-}"
[ -z "$PASS" ] && echo "❌ POSTGRES_PASSWORD vazio" && exit 1

ESCAPED_PASS=$(printf '%s' "$PASS" | sed "s/'/''/g")

# Detectar superuser disponível
DB_USER=""
for u in "${POSTGRES_USER:-}" supabase_admin postgres; do
  [ -z "$u" ] && continue
  if psql -U "$u" -d "$DB_NAME" -tA -c "SELECT 1" >/dev/null 2>&1; then
    DB_USER="$u"; break
  fi
done
[ -z "$DB_USER" ] && echo "❌ Nenhum superuser acessível" && exit 1
echo "   ✅ Conectado como $DB_USER"

R() { psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -c "$1"; }

# ── Roles ──
for role_def in \
  "postgres:LOGIN SUPERUSER CREATEDB CREATEROLE REPLICATION BYPASSRLS" \
  "supabase_admin:LOGIN SUPERUSER CREATEDB CREATEROLE REPLICATION BYPASSRLS" \
  "supabase_auth_admin:LOGIN NOINHERIT CREATEROLE CREATEDB" \
  "supabase_storage_admin:LOGIN NOINHERIT CREATEROLE CREATEDB BYPASSRLS" \
  "authenticator:LOGIN NOINHERIT" \
  "anon:NOLOGIN NOINHERIT" \
  "authenticated:NOLOGIN NOINHERIT" \
  "service_role:NOLOGIN NOINHERIT BYPASSRLS"; do
  name="${role_def%%:*}"
  opts="${role_def#*:}"
  R "DO \$\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='$name') THEN CREATE ROLE $name WITH $opts; END IF; END \$\$;"
done

# ── Senhas ──
for role in postgres supabase_admin supabase_auth_admin supabase_storage_admin authenticator; do
  R "ALTER ROLE $role WITH PASSWORD '${ESCAPED_PASS}';"
done

# ── Grants de roles ──
R "GRANT anon TO authenticator;"
R "GRANT authenticated TO authenticator;"
R "GRANT service_role TO authenticator;"
R "GRANT anon TO supabase_storage_admin;"
R "GRANT authenticated TO supabase_storage_admin;"
R "GRANT service_role TO supabase_storage_admin;"

# ── Database ──
R "ALTER DATABASE \"${DB_NAME}\" OWNER TO supabase_admin;"
R "GRANT CONNECT, TEMP ON DATABASE \"${DB_NAME}\" TO anon, authenticated, service_role, authenticator, supabase_auth_admin, supabase_storage_admin;"
R "GRANT CREATE ON DATABASE \"${DB_NAME}\" TO supabase_auth_admin, supabase_storage_admin;"

# ── Search paths ──
R "ALTER ROLE supabase_auth_admin SET search_path = auth, public;"
R "ALTER ROLE supabase_storage_admin SET search_path = storage, public;"
R "ALTER ROLE authenticator SET search_path = public, auth, storage;"
R "ALTER ROLE supabase_auth_admin IN DATABASE \"${DB_NAME}\" SET search_path = auth, public;"
R "ALTER ROLE supabase_storage_admin IN DATABASE \"${DB_NAME}\" SET search_path = storage, public;"
R "ALTER ROLE authenticator IN DATABASE \"${DB_NAME}\" SET search_path = public, auth, storage;"

# ── Schemas ──
R "CREATE SCHEMA IF NOT EXISTS extensions;"
R "CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;"
R "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\" WITH SCHEMA extensions;"
R "GRANT USAGE ON SCHEMA extensions TO supabase_auth_admin, supabase_storage_admin, authenticator, anon, authenticated, service_role;"
R "CREATE SCHEMA IF NOT EXISTS auth AUTHORIZATION supabase_auth_admin;"
R "ALTER SCHEMA auth OWNER TO supabase_auth_admin;"
R "CREATE SCHEMA IF NOT EXISTS storage AUTHORIZATION supabase_storage_admin;"
R "ALTER SCHEMA storage OWNER TO supabase_storage_admin;"

# ── Funções auth (criadas como supabase_auth_admin para ownership correta) ──
psql -v ON_ERROR_STOP=1 -U supabase_auth_admin -d "$DB_NAME" <<'EOSQL'
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid,
    NULLIF((NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'), '')::uuid
  );
$$;

CREATE OR REPLACE FUNCTION auth.role()
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claim.role', true), '')::text,
    NULLIF((NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'), '')::text
  );
$$;

CREATE OR REPLACE FUNCTION auth.email()
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claim.email', true), '')::text,
    NULLIF((NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email'), '')::text
  );
$$;
EOSQL

# ── Grants de schema ──
R "GRANT USAGE ON SCHEMA auth TO supabase_auth_admin, authenticator, anon, authenticated, service_role;"
R "GRANT CREATE ON SCHEMA auth TO supabase_auth_admin;"
R "GRANT ALL ON ALL TABLES IN SCHEMA auth TO supabase_auth_admin;"
R "GRANT ALL ON ALL SEQUENCES IN SCHEMA auth TO supabase_auth_admin;"
R "GRANT ALL ON ALL ROUTINES IN SCHEMA auth TO supabase_auth_admin;"
R "GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated, service_role, authenticator;"
R "GRANT EXECUTE ON FUNCTION auth.role() TO anon, authenticated, service_role, authenticator;"
R "GRANT EXECUTE ON FUNCTION auth.email() TO anon, authenticated, service_role, authenticator;"
R "ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON TABLES TO supabase_auth_admin;"
R "ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON SEQUENCES TO supabase_auth_admin;"
R "ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON ROUTINES TO supabase_auth_admin;"

R "GRANT USAGE, CREATE ON SCHEMA storage TO supabase_storage_admin;"
R "GRANT ALL ON ALL TABLES IN SCHEMA storage TO supabase_storage_admin;"
R "GRANT ALL ON ALL SEQUENCES IN SCHEMA storage TO supabase_storage_admin;"
R "GRANT ALL ON ALL ROUTINES IN SCHEMA storage TO supabase_storage_admin;"
R "GRANT USAGE ON SCHEMA storage TO authenticator, anon, authenticated, service_role;"

R "GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role, authenticator;"
R "GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;"
R "GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;"
R "GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO anon, authenticated, service_role;"
R "ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;"
R "ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;"
R "ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;"

echo "✅ Bootstrap concluído!"
