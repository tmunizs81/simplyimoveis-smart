#!/bin/bash
# ============================================================
# fix-vps-admin.sh — Recuperação completa do admin self-hosted
# Foco: boot de functions + RLS/admin + auth/grants + storage
# Uso: cd /opt/simply-imoveis/docker && sudo bash fix-vps-admin.sh
# Versão: 2026-03-15-v2
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SQL_FILE="$SCRIPT_DIR/sql/selfhosted-admin-recovery.sql"

echo "=========================================="
echo "  Simply Imóveis — Recovery VPS Admin"
echo "=========================================="

[ ! -f .env ] && echo "❌ .env não encontrado em $SCRIPT_DIR" && exit 1
[ ! -f "$SQL_FILE" ] && echo "❌ SQL de recovery não encontrado: $SQL_FILE" && exit 1

read_env() { grep -E "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"; }

POSTGRES_PASSWORD=$(read_env "POSTGRES_PASSWORD")
POSTGRES_DB=$(read_env "POSTGRES_DB"); POSTGRES_DB="${POSTGRES_DB:-simply_db}"
KONG_HTTP_PORT=$(read_env "KONG_HTTP_PORT"); KONG_HTTP_PORT="${KONG_HTTP_PORT:-8000}"
ANON_KEY=$(read_env "ANON_KEY")
SERVICE_ROLE_KEY=$(read_env "SERVICE_ROLE_KEY")
DB_CONTAINER="simply-db"

for required_var in POSTGRES_PASSWORD JWT_SECRET ANON_KEY SERVICE_ROLE_KEY SITE_DOMAIN; do
  val=$(read_env "$required_var")
  if [ -z "$val" ] || [ "$val" = "CHANGE_ME" ]; then
    echo "❌ Variável obrigatória ausente/inválida: $required_var"
    exit 1
  fi
done

echo ""
echo "1️⃣  Verificando containers essenciais..."
for c in simply-db simply-auth simply-rest simply-storage simply-functions simply-kong; do
  st=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo "not_found")
  if [ "$st" != "running" ]; then
    echo "❌ Container $c não está rodando ($st)"
    exit 1
  fi
  echo "   ✅ $c"
done

# Descobrir usuário de banco funcional
DB_USER=""
for candidate in "$(read_env "POSTGRES_USER")" supabase_admin postgres; do
  [ -z "$candidate" ] && continue
  RESULT=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
    psql -tA -w -h 127.0.0.1 -U "$candidate" -d "$POSTGRES_DB" -c "SELECT 1" 2>/dev/null || true)
  if [ "$RESULT" = "1" ]; then DB_USER="$candidate"; break; fi
done

if [ -z "$DB_USER" ]; then
  echo "❌ Não foi possível conectar no PostgreSQL"
  exit 1
fi

echo "   ✅ Conectado no banco como $DB_USER"

run_psql() {
  docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
    psql -v ON_ERROR_STOP=1 -w -h 127.0.0.1 -U "$DB_USER" -d "$POSTGRES_DB"
}

check_functions_boot() {
  local logs
  logs=$(docker logs simply-functions --tail=120 2>&1 || true)

  if echo "$logs" | grep -Eqi "main worker boot error|worker boot error|boot error"; then
    echo "❌ Functions runtime: boot error detectado"
    echo "$logs" | grep -Ei "main worker boot error|worker boot error|boot error" | tail -n 3
    return 1
  fi

  local crud_status
  crud_status=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://127.0.0.1:${KONG_HTTP_PORT}/functions/v1/admin-crud" \
    -H "apikey: ${ANON_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"action":"select","table":"properties"}' 2>/dev/null || echo "000")

  if [ "$crud_status" != "401" ] && [ "$crud_status" != "403" ]; then
    echo "❌ admin-crud não respondeu como esperado (HTTP $crud_status)"
    return 1
  fi

  echo "   ✅ Functions runtime sem boot error (admin-crud HTTP $crud_status)"
  return 0
}

echo ""
echo "2️⃣  Sincronizando e validando Edge Functions..."
bash sync-functions.sh "$SCRIPT_DIR/../supabase/functions" "$SCRIPT_DIR/volumes/functions"
docker compose up -d --force-recreate functions
sleep 5
check_functions_boot

echo ""
echo "3️⃣  Aplicando SQL completo de correção (schema/RLS/triggers)..."
run_psql < "$SQL_FILE"
echo "   ✅ SQL aplicado"

echo ""
echo "4️⃣  Reaplicando auth roles/grants e funções auxiliares..."
bash sync-db-passwords.sh

echo ""
echo "5️⃣  Reaplicando buckets e policies de storage..."
bash ensure-storage-buckets.sh

echo ""
echo "6️⃣  Reiniciando serviços de API..."
docker compose up -d --force-recreate auth rest storage kong functions
sleep 8

check_functions_boot

echo ""
echo "7️⃣  Smoke tests de API..."
AUTH_ST=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${KONG_HTTP_PORT}/auth/v1/settings" -H "apikey: ${ANON_KEY}" 2>/dev/null || echo "000")
REST_ST=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${KONG_HTTP_PORT}/rest/v1/" -H "apikey: ${SERVICE_ROLE_KEY}" -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" 2>/dev/null || echo "000")

if [ "$AUTH_ST" != "200" ]; then
  echo "❌ Auth falhou (HTTP $AUTH_ST)"
  exit 1
fi

if [ "$REST_ST" = "000" ] || [ "$REST_ST" -ge 500 ] 2>/dev/null; then
  echo "❌ REST falhou (HTTP $REST_ST)"
  exit 1
fi

echo "   ✅ Auth HTTP $AUTH_ST"
echo "   ✅ REST HTTP $REST_ST"

echo ""
echo "8️⃣  Verificação final de admin role..."
ADMIN_COUNT=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
  psql -tA -w -h 127.0.0.1 -U "$DB_USER" -d "$POSTGRES_DB" \
  -c "SELECT count(*) FROM public.user_roles WHERE role='admin';" 2>/dev/null || echo "0")
ADMIN_COUNT=$(echo "$ADMIN_COUNT" | tr -d '[:space:]')

if [ "$ADMIN_COUNT" = "0" ]; then
  echo "⚠️ Nenhum admin encontrado. Rode: bash create-admin.sh email senha"
else
  echo "   ✅ $ADMIN_COUNT admin(s) configurado(s)"
fi

echo ""
echo "=========================================="
echo "  ✅ Recovery concluído com sucesso"
echo "=========================================="
echo ""
echo "Próximos passos:" 
echo "  1. bash validate-install.sh"
echo "  2. Login em /admin"
echo "  3. Testar CRUD: Imóveis, Leads, Inquilinos, Aluguéis, Vistorias"
echo ""
