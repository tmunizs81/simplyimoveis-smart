#!/bin/bash
# ============================================================
# Reparo completo: permissões + auth.uid() + edge functions
# Uso: bash repair-runtime-db.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

[ ! -f .env ] && echo "❌ .env não encontrado" && exit 1

read_env() { grep -E "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"; }

POSTGRES_PASSWORD=$(read_env "POSTGRES_PASSWORD")
POSTGRES_DB=$(read_env "POSTGRES_DB")
POSTGRES_DB="${POSTGRES_DB:-simply_db}"
DB_CONTAINER="simply-db"

run_sql() {
  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
    psql -v ON_ERROR_STOP=1 -w -h 127.0.0.1 -U supabase_admin -d "$POSTGRES_DB" -c "$1"
}

run_sql_quiet() {
  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
    psql -tA -w -h 127.0.0.1 -U supabase_admin -d "$POSTGRES_DB" 2>/dev/null <<EOSQL | tail -1 | tr -d '[:space:]'
$1
EOSQL
}

echo "🛠️  Etapa 1/5: Sincronizando credenciais e permissões..."
bash sync-db-passwords.sh

echo ""
echo "🛠️  Etapa 2/5: Sincronizando Edge Functions..."
bash sync-functions.sh

echo ""
echo "🛠️  Etapa 3/5: Testando auth.uid() com JWT simulado..."

# Simula como PostgREST seta os GUCs (legacy mode = true)
TEST_UID=$(docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
  psql -tA -w -h 127.0.0.1 -U supabase_admin -d "$POSTGRES_DB" 2>/dev/null <<'EOSQL'
DO $$ BEGIN
  PERFORM set_config('request.jwt.claim.sub', 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
END $$;
SELECT auth.uid();
EOSQL
)
TEST_UID=$(echo "$TEST_UID" | grep -v '^$' | grep -v '^DO$' | tr -d '[:space:]')

if [ "$TEST_UID" = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" ]; then
  echo "   ✅ auth.uid() funciona corretamente!"
else
  echo "   ❌ auth.uid() retornou: '$TEST_UID' (esperado: aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee)"
  echo "   Tentando recriar..."
  docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
    psql -v ON_ERROR_STOP=1 -w -h 127.0.0.1 -U supabase_admin -d "$POSTGRES_DB" <<'EOSQL'
DROP FUNCTION IF EXISTS auth.uid() CASCADE;
DROP FUNCTION IF EXISTS auth.role() CASCADE;
DROP FUNCTION IF EXISTS auth.email() CASCADE;

CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid LANGUAGE sql STABLE
SET search_path = ''
AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claim.sub', true), ''),
    (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid;
$$;

CREATE OR REPLACE FUNCTION auth.role()
RETURNS text LANGUAGE sql STABLE
SET search_path = ''
AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claim.role', true), ''),
    (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text;
$$;

CREATE OR REPLACE FUNCTION auth.email()
RETURNS text LANGUAGE sql STABLE
SET search_path = ''
AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claim.email', true), ''),
    (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
  )::text;
$$;

GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated, service_role, authenticator;
GRANT EXECUTE ON FUNCTION auth.role() TO anon, authenticated, service_role, authenticator;
GRANT EXECUTE ON FUNCTION auth.email() TO anon, authenticated, service_role, authenticator;
EOSQL
  echo "   Retestando..."
  TEST_UID2=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
    psql -tA -w -h 127.0.0.1 -U supabase_admin -d "$POSTGRES_DB" 2>/dev/null <<'EOSQL2'
DO $$ BEGIN
  PERFORM set_config('request.jwt.claim.sub', 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee', true);
END $$;
SELECT auth.uid();
EOSQL2
  )
  TEST_UID2=$(echo "$TEST_UID2" | grep -v '^$' | grep -v '^DO$' | tr -d '[:space:]')
  if [ "$TEST_UID2" = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" ]; then
    echo "   ✅ auth.uid() agora funciona!"
  else
    echo "   ❌ auth.uid() AINDA falha: '$TEST_UID2'"
    echo "   Verifique manualmente."
  fi
fi

echo ""
echo "🛠️  Etapa 4/5: Reiniciando serviços..."
docker compose restart rest
sleep 5
docker compose up -d --force-recreate functions
sleep 10

echo ""
echo "🛠️  Etapa 5/5: Validando..."
bash validate-install.sh

echo ""
echo "✅ Reparo concluído!"
