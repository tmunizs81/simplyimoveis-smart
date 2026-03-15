#!/bin/bash
# ============================================================
# Sincroniza senhas dos roles internos do Supabase
# Uso: bash sync-db-passwords.sh [--quiet]
# Versão: 2026-03-15-v10
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
DB_CONTAINER="simply-db"

[ -z "${POSTGRES_PASSWORD:-}" ] && echo "❌ POSTGRES_PASSWORD vazio" && exit 1

log() { [ "$QUIET" = false ] && echo "$1"; }

pg_exec() {
  timeout 45s docker exec -i \
    -e PGPASSWORD="$POSTGRES_PASSWORD" \
    "$DB_CONTAINER" \
    psql -v ON_ERROR_STOP=1 -w -U postgres -d "$POSTGRES_DB" "$@"
}

pg_query_trim() {
  timeout 15s docker exec -i \
    -e PGPASSWORD="$POSTGRES_PASSWORD" \
    "$DB_CONTAINER" \
    psql -tA -w -U postgres -d "$POSTGRES_DB" -c "$1" 2>/dev/null | tr -d '[:space:]'
}

log "🔧 Sincronizando credenciais..."

log "   Aguardando banco (container + healthcheck)..."
for i in {1..30}; do
  DB_STATUS=$(docker inspect -f '{{.State.Status}}' "$DB_CONTAINER" 2>/dev/null || echo "missing")
  DB_HEALTH=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$DB_CONTAINER" 2>/dev/null || echo "unknown")

  if [ "$DB_STATUS" = "running" ] && { [ "$DB_HEALTH" = "healthy" ] || [ "$DB_HEALTH" = "none" ]; }; then
    log "   ✅ Banco pronto (status=$DB_STATUS, health=$DB_HEALTH)"
    break
  fi

  log "   ⏳ tentativa $i/30 (status=$DB_STATUS, health=$DB_HEALTH)"
  [ "$i" = "30" ] && echo "❌ Banco não ficou pronto em tempo hábil" && exit 1
  sleep 2
done

log "   Validando conexão SQL..."
for i in {1..20}; do
  if pg_query_trim "SELECT 1;" >/dev/null 2>&1; then
    log "   ✅ Conexão SQL OK"
    break
  fi

  log "   ⏳ tentativa SQL $i/20"
  [ "$i" = "20" ] && echo "❌ Não foi possível conectar no PostgreSQL com as credenciais do .env" && exit 1
  sleep 2
done

log "   Aguardando roles internos..."
for i in {1..20}; do
  ROLE_OK=$(pg_query_trim "SELECT 1 FROM pg_roles WHERE rolname='supabase_auth_admin'" || true)
  [ "$ROLE_OK" = "1" ] && break
  log "   ⏳ tentativa roles $i/20"
  [ "$i" = "20" ] && echo "❌ Roles internos não foram criados" && exit 1
  sleep 3
done

log "   Aplicando SQL de sincronização..."

ESCAPED_PASS=$(printf '%s' "$POSTGRES_PASSWORD" | sed "s/'/''/g")
TMP_SQL=$(mktemp /tmp/sync-db-XXXXXX.sql)
cat > "$TMP_SQL" <<'EOSQL'
ALTER ROLE supabase_admin WITH PASSWORD '__POSTGRES_PASSWORD__';
ALTER ROLE supabase_auth_admin WITH PASSWORD '__POSTGRES_PASSWORD__';
ALTER ROLE authenticator WITH PASSWORD '__POSTGRES_PASSWORD__';
ALTER ROLE supabase_storage_admin WITH PASSWORD '__POSTGRES_PASSWORD__';

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $body$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth') THEN
    CREATE SCHEMA auth AUTHORIZATION supabase_auth_admin;
  ELSE
    ALTER SCHEMA auth OWNER TO supabase_auth_admin;
  END IF;
END $body$;

DO $body$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'auth' LOOP
    EXECUTE format('ALTER TABLE auth.%I OWNER TO supabase_auth_admin', r.tablename);
  END LOOP;

  FOR r IN SELECT sequence_name FROM information_schema.sequences WHERE sequence_schema = 'auth' LOOP
    EXECUTE format('ALTER SEQUENCE auth.%I OWNER TO supabase_auth_admin', r.sequence_name);
  END LOOP;

  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'auth'
  LOOP
    EXECUTE format('ALTER FUNCTION %s OWNER TO supabase_auth_admin', r.sig);
  END LOOP;

  FOR r IN SELECT viewname FROM pg_views WHERE schemaname = 'auth' LOOP
    EXECUTE format('ALTER VIEW auth.%I OWNER TO supabase_auth_admin', r.viewname);
  END LOOP;

  FOR r IN
    SELECT t.typname
    FROM pg_type t
    JOIN pg_namespace n ON t.typnamespace = n.oid
    WHERE n.nspname = 'auth' AND t.typtype = 'e' AND t.typrelid = 0
  LOOP
    EXECUTE format('ALTER TYPE auth.%I OWNER TO supabase_auth_admin', r.typname);
  END LOOP;
END $body$;

GRANT USAGE ON SCHEMA auth TO supabase_auth_admin, authenticator, anon, authenticated, service_role;
GRANT CREATE ON SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON ALL TABLES IN SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON ALL ROUTINES IN SCHEMA auth TO supabase_auth_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA auth TO authenticator;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA auth TO authenticator;
EOSQL

sed -i "s/__POSTGRES_PASSWORD__/${ESCAPED_PASS}/g" "$TMP_SQL"

if [ "$QUIET" = true ]; then
  pg_exec -f "$TMP_SQL" >/dev/null
else
  pg_exec -f "$TMP_SQL"
fi

rm -f "$TMP_SQL"
log "✅ Credenciais sincronizadas."