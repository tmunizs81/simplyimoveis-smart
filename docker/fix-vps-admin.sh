#!/bin/bash
# ============================================================
# fix-vps-admin.sh — Recovery completo do admin self-hosted
# Uso: cd /opt/simply-imoveis/docker && sudo bash fix-vps-admin.sh
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SQL_FILE="$SCRIPT_DIR/sql/selfhosted-admin-recovery.sql"

echo "=========================================="
echo "  Simply Imóveis — Recovery VPS Admin"
echo "=========================================="

[ ! -f .env ] && echo "❌ .env não encontrado em $SCRIPT_DIR" && exit 1
[ ! -f "$SQL_FILE" ] && echo "❌ SQL não encontrado: $SQL_FILE" && exit 1

read_env() { grep -E "^${1}=" "$SCRIPT_DIR/.env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"; }

POSTGRES_PASSWORD=$(read_env "POSTGRES_PASSWORD")
POSTGRES_DB=$(read_env "POSTGRES_DB"); POSTGRES_DB="${POSTGRES_DB:-simply_db}"
KONG_HTTP_PORT=$(read_env "KONG_HTTP_PORT"); KONG_HTTP_PORT="${KONG_HTTP_PORT:-8000}"
ANON_KEY=$(read_env "ANON_KEY")
SERVICE_ROLE_KEY=$(read_env "SERVICE_ROLE_KEY")
DB_CONTAINER="simply-db"

for required_var in POSTGRES_PASSWORD JWT_SECRET ANON_KEY SERVICE_ROLE_KEY SITE_DOMAIN; do
  val=$(read_env "$required_var")
  [ -z "$val" ] || [ "$val" = "CHANGE_ME" ] && echo "❌ Variável ausente: $required_var" && exit 1
done

echo ""
echo "1️⃣  Verificando containers..."
for c in simply-db simply-auth simply-rest simply-storage simply-functions simply-kong; do
  st=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo "not_found")
  [ "$st" != "running" ] && echo "❌ $c não está rodando ($st)" && exit 1
  echo "   ✅ $c"
done

# Encontrar superuser
DB_USER=""
for candidate in "$(read_env "POSTGRES_USER")" supabase_admin postgres; do
  [ -z "$candidate" ] && continue
  RESULT=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
    psql -tA -w -h 127.0.0.1 -U "$candidate" -d "$POSTGRES_DB" -c "SELECT 1" 2>/dev/null || true)
  [ "$RESULT" = "1" ] && DB_USER="$candidate" && break
done
[ -z "$DB_USER" ] && echo "❌ Não foi possível conectar no PostgreSQL" && exit 1
echo "   ✅ Conectado como $DB_USER"

echo ""
echo "2️⃣  Sincronizando Edge Functions..."
bash sync-functions.sh "$SCRIPT_DIR/../supabase/functions" "$SCRIPT_DIR/volumes/functions"
docker compose up -d --force-recreate functions
sleep 5

echo ""
echo "3️⃣  Reaplicando pipeline de bootstrap completo..."
bash bootstrap-db.sh
echo "   ✅ Bootstrap concluído"

echo ""
echo "6️⃣  Reiniciando serviços..."
docker compose up -d --force-recreate auth rest storage kong functions
sleep 8

echo ""
echo "7️⃣  Smoke tests..."
AUTH_ST=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${KONG_HTTP_PORT}/auth/v1/settings" -H "apikey: ${ANON_KEY}" 2>/dev/null || echo "000")
REST_ST=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${KONG_HTTP_PORT}/rest/v1/" -H "apikey: ${SERVICE_ROLE_KEY}" -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" 2>/dev/null || echo "000")

[ "$AUTH_ST" != "200" ] && echo "❌ Auth falhou (HTTP $AUTH_ST)" && exit 1
echo "   ✅ Auth HTTP $AUTH_ST"
echo "   ✅ REST HTTP $REST_ST"

echo ""
echo "8️⃣  Verificação admin..."
ADMIN_COUNT=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
  psql -tA -w -h 127.0.0.1 -U "$DB_USER" -d "$POSTGRES_DB" \
  -c "SELECT count(*) FROM public.user_roles WHERE role='admin';" 2>/dev/null || echo "0")
ADMIN_COUNT=$(echo "$ADMIN_COUNT" | tr -d '[:space:]')
[ "$ADMIN_COUNT" = "0" ] && echo "⚠️ Nenhum admin. Rode: bash create-admin.sh email senha" || echo "   ✅ $ADMIN_COUNT admin(s)"

echo ""
echo "=========================================="
echo "  ✅ Recovery concluído!"
echo "=========================================="
