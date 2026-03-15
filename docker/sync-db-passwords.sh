#!/bin/bash
# ============================================================
# Sincroniza senhas dos roles internos do Supabase
# Uso: bash sync-db-passwords.sh
# Versão: 2026-03-15-v10-definitive
# Usa docker exec direto (não docker compose exec que trava)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

[ ! -f .env ] && echo "❌ .env não encontrado" && exit 1

POSTGRES_PASSWORD=$(grep -E '^POSTGRES_PASSWORD=' .env | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
POSTGRES_DB=$(grep -E '^POSTGRES_DB=' .env | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
POSTGRES_DB="${POSTGRES_DB:-simply_db}"

[ -z "${POSTGRES_PASSWORD:-}" ] && echo "❌ POSTGRES_PASSWORD vazio" && exit 1

DB_CONTAINER="simply-db"

echo "🔧 Sincronizando credenciais..."

# ── 1. Checar container rodando ──
echo "   Verificando container ${DB_CONTAINER}..."
DB_STATUS=$(docker inspect -f '{{.State.Status}}' "$DB_CONTAINER" 2>/dev/null || echo "not_found")
if [ "$DB_STATUS" != "running" ]; then
  echo "❌ Container $DB_CONTAINER não está rodando (status: $DB_STATUS)"
  echo "   Rode: docker compose up -d db"
  exit 1
fi
echo "   ✅ Container rodando"

# ── 2. Testar conexão SQL (com retry simples) ──
echo "   Testando conexão SQL..."
for i in 1 2 3 4 5 6 7 8 9 10; do
  RESULT=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
    psql -tA -w -U postgres -d "$POSTGRES_DB" -c "SELECT 1" 2>&1) && break
  echo "   ⏳ tentativa $i/10..."
  sleep 3
done

if [ "${RESULT:-}" != "1" ]; then
  echo "❌ Não foi possível conectar ao PostgreSQL"
  echo "   Resultado: $RESULT"
  exit 1
fi
echo "   ✅ Conexão SQL OK"

# ── 3. Verificar roles ──
echo "   Verificando roles internos..."
ROLE_CHECK=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
  psql -tA -w -U postgres -d "$POSTGRES_DB" \
  -c "SELECT string_agg(rolname, ',') FROM pg_roles WHERE rolname IN ('supabase_admin','supabase_auth_admin','authenticator','supabase_storage_admin');" 2>/dev/null || echo "")

echo "   Roles encontrados: ${ROLE_CHECK:-nenhum}"

# ── 4. Aplicar senhas ──
echo "   Aplicando senhas..."
ESCAPED_PASS=$(printf '%s' "$POSTGRES_PASSWORD" | sed "s/'/''/g")

docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
  psql -v ON_ERROR_STOP=0 -w -U postgres -d "$POSTGRES_DB" <<EOSQL
DO \$\$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_admin') THEN
    EXECUTE 'ALTER ROLE supabase_admin WITH PASSWORD ''${ESCAPED_PASS}''';
    RAISE NOTICE 'supabase_admin OK';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
    EXECUTE 'ALTER ROLE supabase_auth_admin WITH PASSWORD ''${ESCAPED_PASS}''';
    RAISE NOTICE 'supabase_auth_admin OK';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticator') THEN
    EXECUTE 'ALTER ROLE authenticator WITH PASSWORD ''${ESCAPED_PASS}''';
    RAISE NOTICE 'authenticator OK';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_storage_admin') THEN
    EXECUTE 'ALTER ROLE supabase_storage_admin WITH PASSWORD ''${ESCAPED_PASS}''';
    RAISE NOTICE 'supabase_storage_admin OK';
  END IF;
END \$\$;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth') THEN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
      CREATE SCHEMA auth AUTHORIZATION supabase_auth_admin;
    END IF;
  ELSE
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
      ALTER SCHEMA auth OWNER TO supabase_auth_admin;
    END IF;
  END IF;
END \$\$;

GRANT USAGE ON SCHEMA auth TO supabase_auth_admin, authenticator, anon, authenticated, service_role;
GRANT CREATE ON SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON ALL TABLES IN SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON ALL ROUTINES IN SCHEMA auth TO supabase_auth_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA auth TO authenticator;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA auth TO authenticator;

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role, authenticator;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;
EOSQL

echo "✅ Credenciais sincronizadas com sucesso!"