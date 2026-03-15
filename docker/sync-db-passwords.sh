#!/bin/bash
# ============================================================
# Sincroniza (e repara) roles/senhas internos do banco
# Uso: bash sync-db-passwords.sh
# Versão: 2026-03-15-v15
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

# Helper: run single SQL command
run_sql() {
  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
    psql -w -U "$DB_ADMIN_USER" -d "$POSTGRES_DB" -c "$1" 2>&1 || true
}

# Helper: run SQL file from stdin
run_sql_file() {
  docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
    psql -w -U "$DB_ADMIN_USER" -d "$POSTGRES_DB" 2>&1 || true
}

ESCAPED_PASS=$(printf '%s' "$POSTGRES_PASSWORD" | sed "s/'/''/g")

echo "   Criando roles..."
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

echo "   Definindo senhas..."
run_sql "ALTER ROLE postgres WITH PASSWORD '${ESCAPED_PASS}';"
run_sql "ALTER ROLE supabase_admin WITH PASSWORD '${ESCAPED_PASS}';"
run_sql "ALTER ROLE supabase_auth_admin WITH PASSWORD '${ESCAPED_PASS}';"
run_sql "ALTER ROLE supabase_storage_admin WITH PASSWORD '${ESCAPED_PASS}';"
run_sql "ALTER ROLE authenticator WITH PASSWORD '${ESCAPED_PASS}';"

echo "   Configurando grants de roles..."
run_sql "GRANT anon TO authenticator;"
run_sql "GRANT authenticated TO authenticator;"
run_sql "GRANT service_role TO authenticator;"

echo "   Configurando ownership e permissões do database..."
run_sql "ALTER DATABASE \"${POSTGRES_DB}\" OWNER TO supabase_admin;"
run_sql "GRANT CONNECT, TEMP ON DATABASE \"${POSTGRES_DB}\" TO anon, authenticated, service_role, authenticator, supabase_auth_admin, supabase_storage_admin;"
run_sql "GRANT CREATE ON DATABASE \"${POSTGRES_DB}\" TO supabase_auth_admin, supabase_storage_admin;"

echo "   Criando schemas auth e storage..."
run_sql "CREATE SCHEMA IF NOT EXISTS auth AUTHORIZATION supabase_auth_admin;"
run_sql "ALTER SCHEMA auth OWNER TO supabase_auth_admin;"
run_sql "CREATE SCHEMA IF NOT EXISTS storage AUTHORIZATION supabase_storage_admin;"
run_sql "ALTER SCHEMA storage OWNER TO supabase_storage_admin;"

echo "   Configurando search_path dos roles..."
run_sql "ALTER ROLE supabase_auth_admin SET search_path = auth, public;"
run_sql "ALTER ROLE supabase_storage_admin SET search_path = storage, public;"
run_sql "ALTER ROLE authenticator SET search_path = public, auth, storage;"
run_sql "ALTER ROLE supabase_auth_admin IN DATABASE \"${POSTGRES_DB}\" SET search_path = auth, public;"
run_sql "ALTER ROLE supabase_storage_admin IN DATABASE \"${POSTGRES_DB}\" SET search_path = storage, public;"
run_sql "ALTER ROLE authenticator IN DATABASE \"${POSTGRES_DB}\" SET search_path = public, auth, storage;"

echo "   Criando funções auth..."
# Use heredoc with quotes to prevent shell expansion
docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
  psql -w -U "$DB_ADMIN_USER" -d "$POSTGRES_DB" <<'EOSQL'
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

echo "   Aplicando grants finais..."
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

# Verify auth schema exists
echo "   Verificando schema auth..."
AUTH_EXISTS=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
  psql -tA -w -U "$DB_ADMIN_USER" -d "$POSTGRES_DB" \
  -c "SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'auth';" 2>/dev/null || echo "")
if [ "$AUTH_EXISTS" = "auth" ]; then
  echo "   ✅ Schema auth existe"
else
  echo "   ❌ Schema auth NÃO existe - tentando criação forçada..."
  run_sql "CREATE SCHEMA auth AUTHORIZATION supabase_auth_admin;"
fi

# Verify storage schema exists
STORAGE_EXISTS=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
  psql -tA -w -U "$DB_ADMIN_USER" -d "$POSTGRES_DB" \
  -c "SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'storage';" 2>/dev/null || echo "")
if [ "$STORAGE_EXISTS" = "storage" ]; then
  echo "   ✅ Schema storage existe"
else
  echo "   ❌ Schema storage NÃO existe - tentando criação forçada..."
  run_sql "CREATE SCHEMA storage AUTHORIZATION supabase_storage_admin;"
fi

echo "✅ Credenciais sincronizadas com sucesso!"
