#!/bin/bash
# ============================================================
# Reaplica senhas, roles e grants (para updates/reparos)
# Uso: bash sync-db-passwords.sh
# Versão: 2026-03-15-v18-simplified
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

[ ! -f .env ] && echo "❌ .env não encontrado" && exit 1

read_env() { grep -E "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"; }

POSTGRES_PASSWORD=$(read_env "POSTGRES_PASSWORD")
POSTGRES_DB=$(read_env "POSTGRES_DB"); POSTGRES_DB="${POSTGRES_DB:-simply_db}"
DB_CONTAINER="simply-db"

[ -z "${POSTGRES_PASSWORD:-}" ] && echo "❌ POSTGRES_PASSWORD vazio" && exit 1

echo "🔧 Sincronizando credenciais..."

# Verificar container
DB_STATUS=$(docker inspect -f '{{.State.Status}}' "$DB_CONTAINER" 2>/dev/null || echo "not_found")
[ "$DB_STATUS" != "running" ] && echo "❌ Container $DB_CONTAINER não rodando ($DB_STATUS)" && exit 1

# Encontrar superuser
DB_USER=""
for candidate in "$(read_env "POSTGRES_USER")" supabase_admin postgres; do
  [ -z "$candidate" ] && continue
  RESULT=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
    psql -tA -w -h 127.0.0.1 -U "$candidate" -d "$POSTGRES_DB" -c "SELECT 1" 2>/dev/null || true)
  if [ "$RESULT" = "1" ]; then DB_USER="$candidate"; break; fi
done

# Retry se não conectou (banco ainda iniciando)
if [ -z "$DB_USER" ]; then
  echo "   ⏳ Aguardando banco..."
  for i in {1..20}; do
    for candidate in supabase_admin postgres; do
      RESULT=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
        psql -tA -w -h 127.0.0.1 -U "$candidate" -d "$POSTGRES_DB" -c "SELECT 1" 2>/dev/null || true)
      [ "$RESULT" = "1" ] && DB_USER="$candidate" && break 2
    done
    sleep 2
  done
fi

[ -z "$DB_USER" ] && echo "❌ Não foi possível conectar ao PostgreSQL" && exit 1
echo "   ✅ Conectado como $DB_USER"

R() {
  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
    psql -v ON_ERROR_STOP=1 -w -h 127.0.0.1 -U "$DB_USER" -d "$POSTGRES_DB" -c "$1"
}

ESCAPED_PASS=$(printf '%s' "$POSTGRES_PASSWORD" | sed "s/'/''/g")

# Senhas
echo "   Aplicando senhas..."
for role in postgres supabase_admin supabase_auth_admin supabase_storage_admin authenticator; do
  R "ALTER ROLE $role WITH PASSWORD '${ESCAPED_PASS}';" >/dev/null 2>&1 || true
done

# Grants
echo "   Aplicando grants..."
R "GRANT anon TO authenticator;" >/dev/null 2>&1 || true
R "GRANT authenticated TO authenticator;" >/dev/null 2>&1 || true
R "GRANT service_role TO authenticator;" >/dev/null 2>&1 || true

# Schemas
R "CREATE SCHEMA IF NOT EXISTS extensions;" >/dev/null 2>&1 || true
R "CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;" >/dev/null 2>&1 || true
R "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\" WITH SCHEMA extensions;" >/dev/null 2>&1 || true
R "CREATE SCHEMA IF NOT EXISTS auth AUTHORIZATION supabase_auth_admin;" >/dev/null 2>&1 || true
R "CREATE SCHEMA IF NOT EXISTS storage AUTHORIZATION supabase_storage_admin;" >/dev/null 2>&1 || true

# Auth functions (drop + recreate como supabase_auth_admin)
echo "   Recriando funções auth..."
R "DROP FUNCTION IF EXISTS auth.uid() CASCADE;" >/dev/null 2>&1 || true
R "DROP FUNCTION IF EXISTS auth.role() CASCADE;" >/dev/null 2>&1 || true
R "DROP FUNCTION IF EXISTS auth.email() CASCADE;" >/dev/null 2>&1 || true

docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
  psql -v ON_ERROR_STOP=1 -w -h 127.0.0.1 -U supabase_auth_admin -d "$POSTGRES_DB" <<'EOSQL'
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

# Schema grants
echo "   Aplicando grants de schema..."
R "GRANT USAGE ON SCHEMA auth TO supabase_auth_admin, authenticator, anon, authenticated, service_role;"
R "GRANT CREATE ON SCHEMA auth TO supabase_auth_admin;"
R "GRANT ALL ON ALL TABLES IN SCHEMA auth TO supabase_auth_admin;"
R "GRANT ALL ON ALL SEQUENCES IN SCHEMA auth TO supabase_auth_admin;"
R "GRANT ALL ON ALL ROUTINES IN SCHEMA auth TO supabase_auth_admin;"
R "GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated, service_role, authenticator;"
R "GRANT EXECUTE ON FUNCTION auth.role() TO anon, authenticated, service_role, authenticator;"
R "GRANT EXECUTE ON FUNCTION auth.email() TO anon, authenticated, service_role, authenticator;"

R "GRANT USAGE, CREATE ON SCHEMA storage TO supabase_storage_admin;"
R "GRANT ALL ON ALL TABLES IN SCHEMA storage TO supabase_storage_admin;"
R "GRANT ALL ON ALL SEQUENCES IN SCHEMA storage TO supabase_storage_admin;"
R "GRANT USAGE ON SCHEMA storage TO authenticator, service_role;"

R "GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role, authenticator;"
R "GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;"
R "GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;"
R "GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO anon, authenticated, service_role;"
R "ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;"
R "ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;"
R "ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;"

echo "✅ Credenciais sincronizadas!"
