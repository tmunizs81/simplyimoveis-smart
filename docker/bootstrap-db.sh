#!/bin/bash
# ============================================================
# Simply Imóveis - Bootstrap determinístico de banco + storage
# Pipeline: sync credenciais -> core schema -> storage schema/policies
# Uso: bash bootstrap-db.sh
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
ENV_FILE="$SCRIPT_DIR/.env"
CORE_SQL="$SCRIPT_DIR/sql/selfhosted-admin-recovery.sql"
STORAGE_SQL="$SCRIPT_DIR/sql/bootstrap-storage.sql"

fail() {
  echo -e "${RED}❌ $1${NC}"
  exit 1
}

require_file() {
  local file="$1"
  [ -f "$file" ] || fail "Arquivo obrigatório ausente: $file"
}

read_env() {
  local key="$1"
  grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"
}

compose() {
  docker compose -f "$COMPOSE_FILE" --project-directory "$SCRIPT_DIR" "$@"
}

run_db_sql() {
  local sql="$1"
  compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" db \
    psql -tA -w -h 127.0.0.1 -U "$DB_ADMIN_USER" -d "$POSTGRES_DB" -c "$sql"
}

run_db_file() {
  local file="$1"
  local label="$2"

  require_file "$file"
  echo -e "${BLUE}🧱 ${label}${NC}"
  echo -e "   SQL: $(realpath "$file")"

  compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" db \
    psql -v ON_ERROR_STOP=1 -w -h 127.0.0.1 -U "$DB_ADMIN_USER" -d "$POSTGRES_DB" < "$file"

  echo -e "   ${GREEN}✅ ${label} aplicado${NC}"
}

echo -e "${BLUE}🔎 Pré-validação do bootstrap...${NC}"
for cmd in docker realpath; do
  command -v "$cmd" >/dev/null 2>&1 || fail "Comando obrigatório ausente: $cmd"
done

for file in "$ENV_FILE" "$COMPOSE_FILE" "$CORE_SQL" "$STORAGE_SQL" "$SCRIPT_DIR/sync-db-passwords.sh" "$SCRIPT_DIR/ensure-storage-buckets.sh"; do
  require_file "$file"
done

echo -e "   ${GREEN}✅ Arquivos obrigatórios encontrados${NC}"

POSTGRES_PASSWORD="$(read_env "POSTGRES_PASSWORD")"
POSTGRES_DB="$(read_env "POSTGRES_DB")"; POSTGRES_DB="${POSTGRES_DB:-simply_db}"
DB_ADMIN_USER="$(read_env "POSTGRES_USER")"; DB_ADMIN_USER="${DB_ADMIN_USER:-supabase_admin}"

[ -z "${POSTGRES_PASSWORD:-}" ] && fail "POSTGRES_PASSWORD vazio no $ENV_FILE"

echo -e "${BLUE}🐘 Subindo DB (se necessário)...${NC}"
compose up -d db >/dev/null

echo -e "${BLUE}⏳ Aguardando PostgreSQL...${NC}"
for i in {1..90}; do
  if compose exec -T db pg_isready -U "$DB_ADMIN_USER" -d "$POSTGRES_DB" -q 2>/dev/null; then
    break
  fi
  [ "$i" = "90" ] && fail "PostgreSQL não respondeu em 180s"
  sleep 2
done
echo -e "   ${GREEN}✅ PostgreSQL pronto${NC}"

echo -e "${BLUE}🔐 Sincronizando roles/senhas/grants...${NC}"
bash "$SCRIPT_DIR/sync-db-passwords.sh"

run_db_file "$CORE_SQL" "Core schema (types/tables/functions/RLS/policies/grants)"

echo -e "${BLUE}🔎 Validando objetos críticos do core...${NC}"
MISSING_TYPES=$(run_db_sql "
WITH req(name) AS (
  SELECT unnest(ARRAY[
    'app_role','property_type','property_status','contract_status','document_type',
    'invoice_status','lead_source','lead_status','transaction_category','transaction_type'
  ]::text[])
)
SELECT COALESCE(string_agg(req.name, ', '), '')
FROM req
LEFT JOIN pg_type t ON t.typname = req.name
LEFT JOIN pg_namespace n ON n.oid = t.typnamespace AND n.nspname = 'public'
WHERE n.oid IS NULL;" | tr -d '[:space:]')

[ -n "$MISSING_TYPES" ] && fail "Tipos ausentes após core bootstrap: $MISSING_TYPES"

MISSING_TABLES=$(run_db_sql "
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
WHERE to_regclass('public.' || req.name) IS NULL;" | tr -d '[:space:]')

[ -n "$MISSING_TABLES" ] && fail "Tabelas ausentes após core bootstrap: $MISSING_TABLES"

MISSING_FUNCS=$(run_db_sql "
WITH req(sig) AS (
  SELECT unnest(ARRAY[
    'public.has_role(uuid,public.app_role)',
    'public.has_role_text(uuid,text)',
    'public.update_updated_at_column()',
    'public.generate_property_short_code()',
    'public.update_property_short_code_on_status_change()'
  ]::text[])
)
SELECT COALESCE(string_agg(sig, ', '), '')
FROM req
WHERE to_regprocedure(sig) IS NULL;" | tr -d '[:space:]')

[ -n "$MISSING_FUNCS" ] && fail "Funções ausentes após core bootstrap: $MISSING_FUNCS"

echo -e "   ${GREEN}✅ Core validado (types/tables/functions)${NC}"

echo -e "${BLUE}🧩 Subindo REST + Storage...${NC}"
compose up -d rest storage >/dev/null

echo -e "${BLUE}⏳ Aguardando schema storage...${NC}"
for i in {1..90}; do
  STORAGE_READY=$(run_db_sql "SELECT CASE WHEN to_regclass('storage.buckets') IS NOT NULL AND to_regclass('storage.objects') IS NOT NULL THEN 'ok' ELSE 'wait' END;" 2>/dev/null || echo "wait")
  [ "$(echo "$STORAGE_READY" | tr -d '[:space:]')" = "ok" ] && break
  [ "$i" = "90" ] && fail "storage.buckets/storage.objects não disponíveis em 180s"
  sleep 2
done
echo -e "   ${GREEN}✅ Storage schema disponível${NC}"

require_file "$STORAGE_SQL"
bash "$SCRIPT_DIR/ensure-storage-buckets.sh"

echo -e "${BLUE}🔎 Validando storage...${NC}"
BUCKETS_OK=$(run_db_sql "
SELECT CASE WHEN (
  SELECT count(*) FROM storage.buckets WHERE id IN (
    'property-media','contract-documents','tenant-documents','inspection-media','sales-documents'
  )
) = 5 THEN 'ok' ELSE 'fail' END;" 2>/dev/null || echo "fail")

[ "$(echo "$BUCKETS_OK" | tr -d '[:space:]')" != "ok" ] && fail "Buckets obrigatórios não foram criados"

STORAGE_POLICIES=$(run_db_sql "
SELECT count(*)
FROM pg_policies
WHERE schemaname='storage'
  AND tablename='objects'
  AND policyname IN (
    'Admins can upload contract-documents','Admins can read contract-documents','Admins can update contract-documents','Admins can delete contract-documents',
    'Admins can upload tenant-documents','Admins can read tenant-documents','Admins can update tenant-documents','Admins can delete tenant-documents',
    'Admins can upload inspection-media','Admins can read inspection-media','Admins can update inspection-media','Admins can delete inspection-media',
    'Admins can upload sales-documents','Admins can read sales-documents','Admins can update sales-documents','Admins can delete sales-documents',
    'Admins can upload property-media','Admins can update property-media','Admins can delete property-media','Public can read property-media'
  );" 2>/dev/null || echo "0")

[ "${STORAGE_POLICIES:-0}" -lt 20 ] && fail "Policies de storage incompletas (${STORAGE_POLICIES}/20)"

echo -e "   ${GREEN}✅ Storage validado (buckets + policies)${NC}"

echo -e "\n${GREEN}✅ Bootstrap DB + Storage concluído com sucesso!${NC}"
