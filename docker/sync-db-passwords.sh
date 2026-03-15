#!/bin/bash
# ============================================================
# Sincroniza (e repara) roles/senhas internos do banco
# Uso: bash sync-db-passwords.sh
# Versão: 2026-03-15-v17
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
      psql -tA -w -h 127.0.0.1 -U "$candidate" -d "$POSTGRES_DB" -c "SELECT 1" 2>/dev/null || true)
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
  echo "❌ Não foi possível conectar ao PostgreSQL"
  exit 1
fi

# Helper: always use -h 127.0.0.1 to force password auth (avoid peer auth failures)
run_sql() {
  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
    psql -v ON_ERROR_STOP=1 -w -h 127.0.0.1 -U "$DB_ADMIN_USER" -d "$POSTGRES_DB" -c "$1"
}

run_sql_as() {
  local user="$1"; shift
  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
    psql -v ON_ERROR_STOP=1 -w -h 127.0.0.1 -U "$user" -d "$POSTGRES_DB" -c "$1"
}

echo "   Criando/garantindo roles internos..."
run_sql "DO \$\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='postgres') THEN CREATE ROLE postgres WITH LOGIN SUPERUSER CREATEDB CREATEROLE REPLICATION BYPASSRLS; END IF; END \$\$;"
run_sql "DO \$\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='supabase_admin') THEN CREATE ROLE supabase_admin WITH LOGIN SUPERUSER CREATEDB CREATEROLE REPLICATION BYPASSRLS; END IF; END \$\$;"
run_sql "DO \$\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='supabase_auth_admin') THEN CREATE ROLE supabase_auth_admin WITH LOGIN NOINHERIT CREATEROLE CREATEDB; END IF; END \$\$;"
run_sql "DO \$\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='supabase_storage_admin') THEN CREATE ROLE supabase_storage_admin WITH LOGIN NOINHERIT CREATEROLE CREATEDB; END IF; END \$\$;"
run_sql "DO \$\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticator') THEN CREATE ROLE authenticator WITH LOGIN NOINHERIT; END IF; END \$\$;"
run_sql "DO \$\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN NOINHERIT; END IF; END \$\$;"
run_sql "DO \$\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN NOINHERIT; END IF; END \$\$;"
run_sql "DO \$\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS; END IF; END \$\$;"

ESCAPED_PASS=$(printf '%s' "$POSTGRES_PASSWORD" | sed "s/'/''/g")

echo "   Aplicando senhas e grants..."
run_sql "ALTER ROLE postgres WITH PASSWORD '${ESCAPED_PASS}';"
run_sql "ALTER ROLE supabase_admin WITH PASSWORD '${ESCAPED_PASS}';"
run_sql "ALTER ROLE supabase_auth_admin WITH PASSWORD '${ESCAPED_PASS}';"
run_sql "ALTER ROLE supabase_storage_admin WITH PASSWORD '${ESCAPED_PASS}';"
run_sql "ALTER ROLE authenticator WITH PASSWORD '${ESCAPED_PASS}';"
run_sql "GRANT anon TO authenticator;"
run_sql "GRANT authenticated TO authenticator;"
run_sql "GRANT service_role TO authenticator;"

run_sql "ALTER DATABASE \"${POSTGRES_DB}\" OWNER TO supabase_admin;"
run_sql "GRANT CONNECT, TEMP ON DATABASE \"${POSTGRES_DB}\" TO anon, authenticated, service_role, authenticator, supabase_auth_admin, supabase_storage_admin;"
run_sql "GRANT CREATE ON DATABASE \"${POSTGRES_DB}\" TO supabase_auth_admin, supabase_storage_admin;"

echo "   Garantindo schemas auth/storage..."
run_sql "CREATE SCHEMA IF NOT EXISTS auth AUTHORIZATION supabase_auth_admin;"
run_sql "ALTER SCHEMA auth OWNER TO supabase_auth_admin;"
run_sql "CREATE SCHEMA IF NOT EXISTS storage AUTHORIZATION supabase_storage_admin;"
run_sql "ALTER SCHEMA storage OWNER TO supabase_storage_admin;"

echo "   Configurando search_path..."
run_sql "ALTER ROLE supabase_auth_admin SET search_path = auth, public;"
run_sql "ALTER ROLE supabase_storage_admin SET search_path = storage, public;"
run_sql "ALTER ROLE authenticator SET search_path = public, auth, storage;"
run_sql "ALTER ROLE supabase_auth_admin IN DATABASE \"${POSTGRES_DB}\" SET search_path = auth, public;"
run_sql "ALTER ROLE supabase_storage_admin IN DATABASE \"${POSTGRES_DB}\" SET search_path = storage, public;"
run_sql "ALTER ROLE authenticator IN DATABASE \"${POSTGRES_DB}\" SET search_path = public, auth, storage;"

echo "   Preparando funções auth (drop + recreate como supabase_auth_admin)..."
# Drop as superuser para garantir, depois recria como supabase_auth_admin
run_sql "DROP FUNCTION IF EXISTS auth.uid() CASCADE;"
run_sql "DROP FUNCTION IF EXISTS auth.role() CASCADE;"
run_sql "DROP FUNCTION IF EXISTS auth.email() CASCADE;"

# Criar funções conectado como supabase_auth_admin (owner correto para GoTrue)
docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
  psql -v ON_ERROR_STOP=1 -w -h 127.0.0.1 -U supabase_auth_admin -d "$POSTGRES_DB" <<'EOSQL'
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid LANGUAGE sql STABLE
AS $$ SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid; $$;

CREATE OR REPLACE FUNCTION auth.role()
RETURNS text LANGUAGE sql STABLE
AS $$ SELECT NULLIF(current_setting('request.jwt.claim.role', true), '')::text; $$;

CREATE OR REPLACE FUNCTION auth.email()
RETURNS text LANGUAGE sql STABLE
AS $$ SELECT NULLIF(current_setting('request.jwt.claim.email', true), '')::text; $$;
EOSQL

echo "   Aplicando grants de schema..."
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

run_sql "GRANT USAGE, CREATE ON SCHEMA storage TO supabase_storage_admin;"
run_sql "GRANT ALL ON ALL TABLES IN SCHEMA storage TO supabase_storage_admin;"
run_sql "GRANT ALL ON ALL SEQUENCES IN SCHEMA storage TO supabase_storage_admin;"
run_sql "GRANT ALL ON ALL ROUTINES IN SCHEMA storage TO supabase_storage_admin;"
run_sql "GRANT USAGE ON SCHEMA storage TO authenticator, service_role;"

run_sql "GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role, authenticator;"
run_sql "GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon, authenticated;"
run_sql "GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;"
run_sql "GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;"
run_sql "GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;"

echo "   Validando privilégios críticos..."
AUTH_CREATE_DB=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" psql -tA -w -h 127.0.0.1 -U "$DB_ADMIN_USER" -d "$POSTGRES_DB" -c "SELECT has_database_privilege('supabase_auth_admin', current_database(), 'CREATE');" | tr -d '[:space:]')
STORAGE_CREATE_DB=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" psql -tA -w -h 127.0.0.1 -U "$DB_ADMIN_USER" -d "$POSTGRES_DB" -c "SELECT has_database_privilege('supabase_storage_admin', current_database(), 'CREATE');" | tr -d '[:space:]')

[ "$AUTH_CREATE_DB" = "t" ] || { echo "❌ supabase_auth_admin sem CREATE no database"; exit 1; }
[ "$STORAGE_CREATE_DB" = "t" ] || { echo "❌ supabase_storage_admin sem CREATE no database"; exit 1; }

AUTH_PATH=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" psql -tA -w -h 127.0.0.1 -U supabase_auth_admin -d "$POSTGRES_DB" -c "SHOW search_path;" | tr -d '[:space:]')
STORAGE_PATH=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" psql -tA -w -h 127.0.0.1 -U supabase_storage_admin -d "$POSTGRES_DB" -c "SHOW search_path;" | tr -d '[:space:]')

[[ "$AUTH_PATH" == *auth* ]] || { echo "❌ search_path supabase_auth_admin inválido: $AUTH_PATH"; exit 1; }
[[ "$STORAGE_PATH" == *storage* ]] || { echo "❌ search_path supabase_storage_admin inválido: $STORAGE_PATH"; exit 1; }

# Probe: supabase_auth_admin cria e dropa tabela no schema auth
docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
  psql -v ON_ERROR_STOP=1 -w -h 127.0.0.1 -U supabase_auth_admin -d "$POSTGRES_DB" \
  -c "CREATE TABLE IF NOT EXISTS auth.__probe(id int); DROP TABLE auth.__probe;" >/dev/null

# Probe: supabase_storage_admin cria e dropa tabela no schema storage
docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
  psql -v ON_ERROR_STOP=1 -w -h 127.0.0.1 -U supabase_storage_admin -d "$POSTGRES_DB" \
  -c "CREATE TABLE IF NOT EXISTS storage.__probe(id int); DROP TABLE storage.__probe;" >/dev/null

# Probe: verificar ownership das funções auth
AUTH_FN_OWNER=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" psql -tA -w -h 127.0.0.1 -U "$DB_ADMIN_USER" -d "$POSTGRES_DB" -c "SELECT proowner::regrole FROM pg_proc WHERE proname='uid' AND pronamespace='auth'::regnamespace;" | tr -d '[:space:]')
[[ "$AUTH_FN_OWNER" == "supabase_auth_admin" ]] || { echo "❌ auth.uid() owner=$AUTH_FN_OWNER (esperado supabase_auth_admin)"; exit 1; }

echo "✅ Credenciais sincronizadas com sucesso!"
