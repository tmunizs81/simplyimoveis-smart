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

[ -f "$ENV_FILE" ] || { echo -e "${RED}❌ .env não encontrado em $ENV_FILE${NC}"; exit 1; }
[ -f "$COMPOSE_FILE" ] || { echo -e "${RED}❌ docker-compose.yml ausente: $COMPOSE_FILE${NC}"; exit 1; }

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

[ -z "$ANON_KEY" ] || [ -z "$SERVICE_ROLE_KEY" ] && { echo -e "${RED}❌ Chaves JWT não definidas no .env${NC}"; exit 1; }
[ -z "$POSTGRES_PASSWORD" ] && { echo -e "${RED}❌ POSTGRES_PASSWORD ausente no .env${NC}"; exit 1; }

PASS=0; FAIL=0; WARN=0

check() {
  local desc="$1" result="$2"
  if [ "$result" = "ok" ]; then
    echo -e "   ${GREEN}✅ $desc${NC}"; ((PASS++))
  elif [ "$result" = "warn" ]; then
    echo -e "   ${YELLOW}⚠️  $desc${NC}"; ((WARN++))
  else
    echo -e "   ${RED}❌ $desc${NC}"; ((FAIL++))
  fi
}

run_sql() {
  compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" db \
    psql -tA -w -h 127.0.0.1 -U "$DB_USER" -d "$POSTGRES_DB" -c "$1" 2>/dev/null || echo ""
}

echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Validação Estrutural do Instalador Docker       ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"

echo -e "\n${BLUE}1. Arquivos essenciais${NC}"
for f in "$CORE_SQL" "$STORAGE_SQL" "$SCRIPT_DIR/bootstrap-db.sh" "$SCRIPT_DIR/sync-db-passwords.sh" "$SCRIPT_DIR/ensure-storage-buckets.sh" "$SCRIPT_DIR/volumes/db/init/00-passwords.sh" "$SCRIPT_DIR/volumes/db/init/01-schema.sql"; do
  [ -f "$f" ] && check "$(realpath "$f")" "ok" || check "Arquivo ausente: $f" "fail"
done

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

echo -e "\n${BLUE}3. Banco (objetos críticos)${NC}"
DB_OK=$(run_sql "SELECT 1;")
[ "$DB_OK" = "1" ] && check "Conexão PostgreSQL" "ok" || check "Conexão PostgreSQL" "fail"

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
  [ -z "$(echo "$MISSING_TYPES" | tr -d '[:space:]')" ] && check "Tipos customizados" "ok" || check "Tipos ausentes: $MISSING_TYPES" "fail"

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
  [ -z "$(echo "$MISSING_TABLES" | tr -d '[:space:]')" ] && check "Tabelas principais" "ok" || check "Tabelas ausentes: $MISSING_TABLES" "fail"

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
  [ -z "$(echo "$MISSING_FUNCS" | tr -d '[:space:]')" ] && check "Funções auxiliares" "ok" || check "Funções ausentes: $MISSING_FUNCS" "fail"

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
  [ -z "$(echo "$MISSING_RLS" | tr -d '[:space:]')" ] && check "RLS habilitado nas tabelas críticas" "ok" || check "RLS ausente em: $MISSING_RLS" "fail"

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
  [ -z "$(echo "$MISSING_POLICIES" | tr -d '[:space:]')" ] && check "Policies críticas" "ok" || check "Policies ausentes: $MISSING_POLICIES" "fail"

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
  [ -z "$(echo "$MISSING_TRIGGERS" | tr -d '[:space:]')" ] && check "Triggers críticos" "ok" || check "Triggers ausentes: $MISSING_TRIGGERS" "fail"
fi

echo -e "\n${BLUE}4. Storage${NC}"
BUCKETS=$(run_sql "SELECT count(*) FROM storage.buckets WHERE id IN ('property-media','contract-documents','tenant-documents','inspection-media','sales-documents');")
[ "${BUCKETS:-0}" -eq 5 ] && check "Buckets obrigatórios (5/5)" "ok" || check "Buckets obrigatórios (${BUCKETS}/5)" "fail"

STORAGE_POLICIES=$(run_sql "SELECT count(*) FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname IN (
'Admins can upload contract-documents','Admins can read contract-documents','Admins can update contract-documents','Admins can delete contract-documents',
'Admins can upload tenant-documents','Admins can read tenant-documents','Admins can update tenant-documents','Admins can delete tenant-documents',
'Admins can upload inspection-media','Admins can read inspection-media','Admins can update inspection-media','Admins can delete inspection-media',
'Admins can upload sales-documents','Admins can read sales-documents','Admins can update sales-documents','Admins can delete sales-documents',
'Admins can upload property-media','Admins can update property-media','Admins can delete property-media','Public can read property-media');")
[ "${STORAGE_POLICIES:-0}" -ge 20 ] && check "Policies storage (${STORAGE_POLICIES}/20)" "ok" || check "Policies storage (${STORAGE_POLICIES}/20)" "fail"

echo -e "\n${BLUE}5. APIs e frontend${NC}"
AUTH_ST=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" "http://127.0.0.1:${KONG_PORT}/auth/v1/settings" -H "apikey: ${ANON_KEY}" 2>/dev/null || echo "000")
[ "$AUTH_ST" = "200" ] && check "Auth API (HTTP $AUTH_ST)" "ok" || check "Auth API (HTTP $AUTH_ST)" "fail"

REST_ST=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" "http://127.0.0.1:${KONG_PORT}/rest/v1/" -H "apikey: ${ANON_KEY}" 2>/dev/null || echo "000")
[ "$REST_ST" = "200" ] && check "REST API (HTTP $REST_ST)" "ok" || check "REST API (HTTP $REST_ST)" "fail"

STORAGE_ST=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" "http://127.0.0.1:${KONG_PORT}/storage/v1/bucket" -H "apikey: ${ANON_KEY}" -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" 2>/dev/null || echo "000")
[ "$STORAGE_ST" = "200" ] && check "Storage API (HTTP $STORAGE_ST)" "ok" || check "Storage API (HTTP $STORAGE_ST)" "warn"

FE_ST=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" "http://127.0.0.1:${FRONTEND_PORT}/" 2>/dev/null || echo "000")
[ "$FE_ST" = "200" ] && check "Frontend (HTTP $FE_ST)" "ok" || check "Frontend (HTTP $FE_ST)" "fail"

echo -e "\n${BLUE}6. Function crítica (admin-crud)${NC}"
CRUD_ST=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" -X POST "http://127.0.0.1:${KONG_PORT}/functions/v1/admin-crud" -H "apikey: ${ANON_KEY}" -H "Content-Type: application/json" -d '{}' 2>/dev/null || echo "000")
[[ "$CRUD_ST" =~ ^(400|401|403)$ ]] && check "admin-crud endpoint (HTTP $CRUD_ST)" "ok" || check "admin-crud endpoint (HTTP $CRUD_ST)" "warn"

echo ""
echo -e "${BLUE}════ Resumo ════${NC}"
echo -e "   ${GREEN}Passed: $PASS${NC}  ${YELLOW}Warnings: $WARN${NC}  ${RED}Failed: $FAIL${NC}"

if [ "$FAIL" -gt 0 ]; then
  echo -e "\n${RED}❌ Validação falhou com $FAIL erro(s) crítico(s).${NC}"
  echo -e "${YELLOW}Debug sugerido:${NC}"
  echo -e "   cd $SCRIPT_DIR && docker compose logs --tail=120 db rest auth storage kong functions"
  echo -e "   cd $SCRIPT_DIR && bash bootstrap-db.sh"
  exit 1
fi

echo -e "\n${GREEN}✅ Validação concluída com sucesso!${NC}"
exit 0
