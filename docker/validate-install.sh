#!/bin/bash
# ============================================================
# Simply Imóveis - Validação estrutural pós-instalação
# Uso: bash validate-install.sh
# Exit 0: OK | Exit 1: falhas críticas
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
CORE_SQL="$SCRIPT_DIR/sql/selfhosted-admin-recovery.sql"
STORAGE_SQL="$SCRIPT_DIR/sql/bootstrap-storage.sql"

[ -f "$ENV_FILE" ] || { echo -e "${RED}ERRO: .env nao encontrado em $ENV_FILE${NC}"; exit 1; }
[ -f "$COMPOSE_FILE" ] || { echo -e "${RED}ERRO: docker-compose.yml ausente: $COMPOSE_FILE${NC}"; exit 1; }

read_env() {
  local key="$1"
  grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"
}

compose() {
  docker compose -f "$COMPOSE_FILE" --project-directory "$SCRIPT_DIR" "$@"
}

KONG_PORT="$(read_env "KONG_HTTP_PORT")"; KONG_PORT="${KONG_PORT:-8000}"
FRONTEND_PORT="$(read_env "FRONTEND_PORT")"; FRONTEND_PORT="${FRONTEND_PORT:-3000}"
ANON_KEY="$(read_env "ANON_KEY")"
SERVICE_ROLE_KEY="$(read_env "SERVICE_ROLE_KEY")"
POSTGRES_PASSWORD="$(read_env "POSTGRES_PASSWORD")"
POSTGRES_DB="$(read_env "POSTGRES_DB")"; POSTGRES_DB="${POSTGRES_DB:-simply_db}"
DB_USER="$(read_env "POSTGRES_USER")"; DB_USER="${DB_USER:-supabase_admin}"

[ -z "$ANON_KEY" ] || [ -z "$SERVICE_ROLE_KEY" ] && { echo -e "${RED}ERRO: Chaves JWT nao definidas no .env${NC}"; exit 1; }
[ -z "$POSTGRES_PASSWORD" ] && { echo -e "${RED}ERRO: POSTGRES_PASSWORD ausente no .env${NC}"; exit 1; }

PASS=0; FAIL=0; WARN=0

check() {
  local desc="$1"
  local result="$2"
  if [ "$result" = "ok" ]; then
    echo -e "   ${GREEN}OK: $desc${NC}"
    PASS=$((PASS + 1))
  elif [ "$result" = "warn" ]; then
    echo -e "   ${YELLOW}WARN: $desc${NC}"
    WARN=$((WARN + 1))
  else
    echo -e "   ${RED}FAIL: $desc${NC}"
    FAIL=$((FAIL + 1))
  fi
}

require_file() {
  local filepath="$1"
  if [ -f "$filepath" ]; then
    check "$filepath" "ok"
  else
    check "Arquivo ausente: $filepath" "fail"
  fi
}

run_sql() {
  compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" db \
    psql -tA -w -h 127.0.0.1 -U "$DB_USER" -d "$POSTGRES_DB" -c "$1" 2>/dev/null || echo ""
}

echo -e "${BLUE}=== Validacao Estrutural do Instalador Docker ===${NC}"

echo -e "\n${BLUE}1. Arquivos essenciais${NC}"
require_file "$CORE_SQL"
require_file "$STORAGE_SQL"
require_file "$SCRIPT_DIR/bootstrap-db.sh"
require_file "$SCRIPT_DIR/sync-db-passwords.sh"
require_file "$SCRIPT_DIR/ensure-storage-buckets.sh"
require_file "$SCRIPT_DIR/volumes/db/init/00-passwords.sh"
require_file "$SCRIPT_DIR/volumes/db/init/01-schema.sql"

echo -e "\n${BLUE}2. Containers${NC}"
for c in simply-db simply-auth simply-rest simply-storage simply-kong simply-functions simply-frontend; do
  st=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo "missing")
  rs=$(docker inspect -f '{{.State.Restarting}}' "$c" 2>/dev/null || echo "false")
  if [ "$st" = "running" ] && [ "$rs" != "true" ]; then
    check "$c" "ok"
  else
    check "$c ($st)" "fail"
  fi
done

echo -e "\n${BLUE}3. Banco (objetos criticos)${NC}"
DB_OK=$(run_sql "SELECT 1;")
if [ "$DB_OK" = "1" ]; then
  check "Conexao PostgreSQL" "ok"
else
  check "Conexao PostgreSQL" "fail"
fi

if [ "$DB_OK" = "1" ]; then
  MISSING_TYPES=$(run_sql "
    WITH req(name) AS (
      SELECT unnest(ARRAY[
        'app_role','property_type','property_status','contract_status','document_type',
        'invoice_status','lead_source','lead_status','transaction_category','transaction_type'
      ]::text[])
    )
    SELECT COALESCE(string_agg(req.name, ', '), '')
    FROM req
    LEFT JOIN pg_type t ON t.typname = req.name
    LEFT JOIN pg_namespace n ON n.oid=t.typnamespace AND n.nspname='public'
    WHERE n.oid IS NULL;")
  if [ -z "$(echo "$MISSING_TYPES" | tr -d '[:space:]')" ]; then
    check "Tipos customizados" "ok"
  else
    check "Tipos ausentes: $MISSING_TYPES" "fail"
  fi

  MISSING_TABLES=$(run_sql "
    WITH req(name) AS (
      SELECT unnest(ARRAY[
        'properties','property_media','contact_submissions','user_roles','leads','tenants',
        'rental_contracts','sales','financial_transactions','property_inspections',
        'inspection_media','scheduled_visits','contract_documents','tenant_documents',
        'sales_documents','property_code_sequences'
      ]::text[])
    )
    SELECT COALESCE(string_agg(req.name, ', '), '')
    FROM req
    WHERE to_regclass('public.' || req.name) IS NULL;")
  if [ -z "$(echo "$MISSING_TABLES" | tr -d '[:space:]')" ]; then
    check "Tabelas principais" "ok"
  else
    check "Tabelas ausentes: $MISSING_TABLES" "fail"
  fi

  MISSING_FUNCS=$(run_sql "
    WITH req(sig) AS (
      SELECT unnest(ARRAY[
        'public.has_role(uuid,public.app_role)',
        'public.update_updated_at_column()',
        'public.generate_property_short_code()',
        'public.update_property_short_code_on_status_change()'
      ]::text[])
    )
    SELECT COALESCE(string_agg(sig, ', '), '') FROM req WHERE to_regprocedure(sig) IS NULL;")
  if [ -z "$(echo "$MISSING_FUNCS" | tr -d '[:space:]')" ]; then
    check "Funcoes auxiliares" "ok"
  else
    check "Funcoes ausentes: $MISSING_FUNCS" "fail"
  fi

  MISSING_RLS=$(run_sql "
    WITH req(tbl) AS (
      SELECT unnest(ARRAY[
        'properties','property_media','contact_submissions','user_roles','leads','tenants',
        'rental_contracts','sales','financial_transactions','property_inspections',
        'inspection_media','scheduled_visits','contract_documents','tenant_documents',
        'sales_documents','property_code_sequences'
      ]::text[])
    )
    SELECT COALESCE(string_agg(req.tbl, ', '), '')
    FROM req
    LEFT JOIN pg_tables t ON t.schemaname='public' AND t.tablename=req.tbl
    WHERE t.rowsecurity IS DISTINCT FROM true;")
  if [ -z "$(echo "$MISSING_RLS" | tr -d '[:space:]')" ]; then
    check "RLS habilitado nas tabelas criticas" "ok"
  else
    check "RLS ausente em: $MISSING_RLS" "fail"
  fi

  MISSING_POLICIES=$(run_sql "
    WITH req(name) AS (
      SELECT unnest(ARRAY[
        'Admins can manage properties','Anyone can view active properties','Admins can manage property media',
        'Admins can manage leads','Admins can manage tenants','Admins can manage contracts','Admins can manage sales',
        'Admins can manage transactions','Admins can manage inspections','Admins can manage inspection media',
        'Admins can manage documents','Admins can manage tenant docs','Admins can manage sale docs',
        'Admins can manage code sequences','Admins can view contacts','Anyone can submit contact',
        'Admins can view visits','Anyone can insert visits','Admins can view roles','Users can view own role'
      ]::text[])
    )
    SELECT COALESCE(string_agg(req.name, ', '), '')
    FROM req
    LEFT JOIN pg_policies p ON p.schemaname='public' AND p.policyname=req.name
    WHERE p.policyname IS NULL;")
  if [ -z "$(echo "$MISSING_POLICIES" | tr -d '[:space:]')" ]; then
    check "Policies criticas" "ok"
  else
    check "Policies ausentes: $MISSING_POLICIES" "fail"
  fi

  MISSING_TRIGGERS=$(run_sql "
    WITH req(name) AS (
      SELECT unnest(ARRAY[
        'set_short_code','update_short_code','update_properties_updated_at','update_tenants_updated_at',
        'update_leads_updated_at','update_rental_contracts_updated_at','update_sales_updated_at',
        'update_property_inspections_updated_at'
      ]::text[])
    )
    SELECT COALESCE(string_agg(req.name, ', '), '')
    FROM req
    LEFT JOIN pg_trigger t ON t.tgname=req.name AND NOT t.tgisinternal
    WHERE t.oid IS NULL;")
  if [ -z "$(echo "$MISSING_TRIGGERS" | tr -d '[:space:]')" ]; then
    check "Triggers criticos" "ok"
  else
    check "Triggers ausentes: $MISSING_TRIGGERS" "fail"
  fi
fi

echo -e "\n${BLUE}4. Storage${NC}"
BUCKETS=$(run_sql "SELECT count(*) FROM storage.buckets WHERE id IN ('property-media','contract-documents','tenant-documents','inspection-media','sales-documents');")
if [ "${BUCKETS:-0}" -eq 5 ]; then
  check "Buckets obrigatorios (5/5)" "ok"
else
  check "Buckets obrigatorios (${BUCKETS:-0}/5)" "fail"
fi

STORAGE_POLICIES=$(run_sql "SELECT count(*) FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname IN (
'Admins can upload contract-documents','Admins can read contract-documents','Admins can update contract-documents','Admins can delete contract-documents',
'Admins can upload tenant-documents','Admins can read tenant-documents','Admins can update tenant-documents','Admins can delete tenant-documents',
'Admins can upload inspection-media','Admins can read inspection-media','Admins can update inspection-media','Admins can delete inspection-media',
'Admins can upload sales-documents','Admins can read sales-documents','Admins can update sales-documents','Admins can delete sales-documents',
'Admins can upload property-media','Admins can update property-media','Admins can delete property-media','Public can read property-media');")
if [ "${STORAGE_POLICIES:-0}" -ge 20 ]; then
  check "Policies storage (${STORAGE_POLICIES}/20)" "ok"
else
  check "Policies storage (${STORAGE_POLICIES:-0}/20)" "fail"
fi

echo -e "\n${BLUE}5. APIs e frontend${NC}"
AUTH_ST=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" "http://127.0.0.1:${KONG_PORT}/auth/v1/settings" -H "apikey: ${ANON_KEY}" 2>/dev/null || echo "000")
if [ "$AUTH_ST" = "200" ]; then check "Auth API (HTTP $AUTH_ST)" "ok"; else check "Auth API (HTTP $AUTH_ST)" "fail"; fi

REST_ST=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" "http://127.0.0.1:${KONG_PORT}/rest/v1/" -H "apikey: ${ANON_KEY}" 2>/dev/null || echo "000")
if [ "$REST_ST" = "200" ]; then check "REST API (HTTP $REST_ST)" "ok"; else check "REST API (HTTP $REST_ST)" "fail"; fi

STORAGE_ST=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" "http://127.0.0.1:${KONG_PORT}/storage/v1/bucket" -H "apikey: ${ANON_KEY}" -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" 2>/dev/null || echo "000")
if [ "$STORAGE_ST" = "200" ]; then check "Storage API (HTTP $STORAGE_ST)" "ok"; else check "Storage API (HTTP $STORAGE_ST)" "warn"; fi

FE_ST=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" "http://127.0.0.1:${FRONTEND_PORT}/" 2>/dev/null || echo "000")
if [ "$FE_ST" = "200" ]; then check "Frontend (HTTP $FE_ST)" "ok"; else check "Frontend (HTTP $FE_ST)" "fail"; fi

echo -e "\n${BLUE}6. Function critica (admin-crud)${NC}"
CRUD_ST=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" -X POST "http://127.0.0.1:${KONG_PORT}/functions/v1/admin-crud" -H "apikey: ${ANON_KEY}" -H "Content-Type: application/json" -d '{}' 2>/dev/null || echo "000")
case "$CRUD_ST" in
  400|401|403) check "admin-crud endpoint (HTTP $CRUD_ST)" "ok" ;;
  *) check "admin-crud endpoint (HTTP $CRUD_ST)" "warn" ;;
esac

echo ""
echo -e "${BLUE}=== Resumo ===${NC}"
echo -e "   ${GREEN}Passed: $PASS${NC}  ${YELLOW}Warnings: $WARN${NC}  ${RED}Failed: $FAIL${NC}"

if [ "$FAIL" -gt 0 ]; then
  echo -e "\n${RED}Validacao falhou com $FAIL erro(s) critico(s).${NC}"
  echo -e "${YELLOW}Debug sugerido:${NC}"
  echo -e "   cd $SCRIPT_DIR && docker compose logs --tail=120 db rest auth storage kong functions"
  echo -e "   cd $SCRIPT_DIR && bash bootstrap-db.sh"
  exit 1
fi

echo -e "\n${GREEN}Validacao concluida com sucesso!${NC}"
exit 0
