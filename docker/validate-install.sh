#!/bin/bash
# ============================================================
# Simply Imóveis - Validação pós-instalação
# Seções: Stack Interno | Endpoints Locais | Banco | Storage | Público (opcional)
# Uso: bash validate-install.sh [--public]
# Exit 0: OK | Exit 1: falhas críticas
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

CHECK_PUBLIC=false
for arg in "$@"; do [ "$arg" = "--public" ] && CHECK_PUBLIC=true; done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
CORE_SQL="$SCRIPT_DIR/sql/selfhosted-admin-recovery.sql"
STORAGE_SQL="$SCRIPT_DIR/sql/bootstrap-storage.sql"

[ -f "$ENV_FILE" ] || { echo -e "${RED}ERRO: .env nao encontrado em $ENV_FILE${NC}"; exit 1; }
[ -f "$COMPOSE_FILE" ] || { echo -e "${RED}ERRO: docker-compose.yml ausente: $COMPOSE_FILE${NC}"; exit 1; }

read_env() {
  grep -E "^${1}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"
}

compose() {
  docker compose -f "$COMPOSE_FILE" --project-directory "$SCRIPT_DIR" "$@"
}

KONG_PORT="$(read_env "KONG_HTTP_PORT")"; KONG_PORT="${KONG_PORT:-8000}"
FRONTEND_PORT="$(read_env "FRONTEND_PORT")"; FRONTEND_PORT="${FRONTEND_PORT:-3000}"
ANON_KEY="$(read_env "ANON_KEY")"
SERVICE_ROLE_KEY="$(read_env "SERVICE_ROLE_KEY")"
JWT_SECRET="$(read_env "JWT_SECRET")"
POSTGRES_PASSWORD="$(read_env "POSTGRES_PASSWORD")"
POSTGRES_DB="$(read_env "POSTGRES_DB")"; POSTGRES_DB="${POSTGRES_DB:-simply_db}"
DB_USER="$(read_env "POSTGRES_USER")"; DB_USER="${DB_USER:-supabase_admin}"
SITE_DOMAIN="$(read_env "SITE_DOMAIN")"

[ -z "$ANON_KEY" ] || [ -z "$SERVICE_ROLE_KEY" ] && { echo -e "${RED}ERRO: Chaves JWT nao definidas no .env${NC}"; exit 1; }
[ -z "$JWT_SECRET" ] && { echo -e "${RED}ERRO: JWT_SECRET ausente no .env${NC}"; exit 1; }
[ -z "$POSTGRES_PASSWORD" ] && { echo -e "${RED}ERRO: POSTGRES_PASSWORD ausente no .env${NC}"; exit 1; }

PASS=0; FAIL=0; WARN=0

check() {
  local desc="$1" result="$2"
  if [ "$result" = "ok" ]; then
    echo -e "   ${GREEN}✓ $desc${NC}"; PASS=$((PASS + 1))
  elif [ "$result" = "warn" ]; then
    echo -e "   ${YELLOW}⚠ $desc${NC}"; WARN=$((WARN + 1))
  else
    echo -e "   ${RED}✗ $desc${NC}"; FAIL=$((FAIL + 1))
  fi
}

require_file() {
  [ -f "$1" ] && check "$1" "ok" || check "Arquivo ausente: $1" "fail"
}

run_sql() {
  compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" db \
    psql -tA -w -h 127.0.0.1 -U "$DB_USER" -d "$POSTGRES_DB" -c "$1" 2>/dev/null || echo ""
}

validate_jwt_role() {
  local token="$1" expected_role="$2"

  python3 - "$token" "$JWT_SECRET" "$expected_role" <<'PY'
import base64
import hashlib
import hmac
import json
import sys
import time

token, secret, expected_role = sys.argv[1], sys.argv[2], sys.argv[3]

def b64decode_urlsafe(value: str) -> bytes:
    value += "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode(value.encode())

status = "invalid"

try:
    parts = token.split('.')
    if len(parts) != 3:
        status = 'invalid-format'
    else:
        header_b64, payload_b64, signature_b64 = parts
        payload = json.loads(b64decode_urlsafe(payload_b64))
        expected_signature = base64.urlsafe_b64encode(
            hmac.new(
                secret.encode(),
                f"{header_b64}.{payload_b64}".encode(),
                hashlib.sha256,
            ).digest()
        ).decode().rstrip('=')

        if not hmac.compare_digest(expected_signature, signature_b64):
            status = 'invalid-signature'
        elif payload.get('role') != expected_role:
            status = f"invalid-role:{payload.get('role')}"
        elif int(payload.get('exp', 0) or 0) <= int(time.time()):
            status = 'expired'
        else:
            status = 'ok'
except Exception as exc:
    status = f'invalid:{type(exc).__name__}'

print(status)
PY
}

echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Simply Imóveis - Validação de Instalação${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════${NC}"

# ==============================================================
# SEÇÃO 1 - Arquivos essenciais
# ==============================================================
echo -e "\n${BLUE}1. Arquivos essenciais${NC}"
require_file "$CORE_SQL"
require_file "$STORAGE_SQL"
require_file "$SCRIPT_DIR/bootstrap-db.sh"
require_file "$SCRIPT_DIR/sync-db-passwords.sh"
require_file "$SCRIPT_DIR/ensure-storage-buckets.sh"
require_file "$SCRIPT_DIR/volumes/db/init/00-passwords.sh"
require_file "$SCRIPT_DIR/volumes/db/init/01-schema.sql"

# ==============================================================
# SEÇÃO 2 - Stack Docker interno (containers)
# ==============================================================
echo -e "\n${BLUE}2. Stack Docker (containers)${NC}"
for c in simply-db simply-auth simply-rest simply-storage simply-kong simply-functions simply-frontend; do
  st=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo "missing")
  rs=$(docker inspect -f '{{.State.Restarting}}' "$c" 2>/dev/null || echo "false")
  if [ "$st" = "running" ] && [ "$rs" != "true" ]; then
    check "$c (running)" "ok"
  else
    check "$c ($st)" "fail"
  fi
done

# ==============================================================
# SEÇÃO 3 - Endpoints locais (127.0.0.1)
# ==============================================================
echo -e "\n${BLUE}3. Endpoints locais (127.0.0.1)${NC}"

FE_ST=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" "http://127.0.0.1:${FRONTEND_PORT}/" 2>/dev/null || echo "000")
if [ "$FE_ST" = "200" ]; then
  check "Frontend local 127.0.0.1:${FRONTEND_PORT} (HTTP $FE_ST)" "ok"
else
  check "Frontend local 127.0.0.1:${FRONTEND_PORT} (HTTP $FE_ST)" "fail"
fi

AUTH_ST=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" "http://127.0.0.1:${KONG_PORT}/auth/v1/settings" -H "apikey: ${ANON_KEY}" 2>/dev/null || echo "000")
if [ "$AUTH_ST" = "200" ]; then
  check "Auth API 127.0.0.1:${KONG_PORT}/auth/v1 (HTTP $AUTH_ST)" "ok"
else
  check "Auth API 127.0.0.1:${KONG_PORT}/auth/v1 (HTTP $AUTH_ST)" "fail"
fi

REST_ST=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" "http://127.0.0.1:${KONG_PORT}/rest/v1/" -H "apikey: ${ANON_KEY}" 2>/dev/null || echo "000")
if [ "$REST_ST" = "200" ]; then
  check "REST API 127.0.0.1:${KONG_PORT}/rest/v1 (HTTP $REST_ST)" "ok"
else
  check "REST API 127.0.0.1:${KONG_PORT}/rest/v1 (HTTP $REST_ST)" "fail"
fi

STORAGE_ST=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" "http://127.0.0.1:${KONG_PORT}/storage/v1/bucket" -H "apikey: ${ANON_KEY}" -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" 2>/dev/null || echo "000")
if [ "$STORAGE_ST" = "200" ]; then
  check "Storage API 127.0.0.1:${KONG_PORT}/storage/v1 (HTTP $STORAGE_ST)" "ok"
else
  check "Storage API 127.0.0.1:${KONG_PORT}/storage/v1 (HTTP $STORAGE_ST)" "warn"
fi

CRUD_ST=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" -X POST "http://127.0.0.1:${KONG_PORT}/functions/v1/admin-crud" -H "apikey: ${ANON_KEY}" -H "Content-Type: application/json" -d '{}' 2>/dev/null || echo "000")
case "$CRUD_ST" in
  400|401|403) check "Edge Function admin-crud (HTTP $CRUD_ST)" "ok" ;;
  *) check "Edge Function admin-crud (HTTP $CRUD_ST)" "warn" ;;
esac

# ==============================================================
# SEÇÃO 4 - Banco de dados (objetos críticos)
# ==============================================================
echo -e "\n${BLUE}4. Banco de dados${NC}"
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
  [ -z "$(echo "$MISSING_FUNCS" | tr -d '[:space:]')" ] && check "Funcoes auxiliares" "ok" || check "Funcoes ausentes: $MISSING_FUNCS" "fail"

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
  [ -z "$(echo "$MISSING_RLS" | tr -d '[:space:]')" ] && check "RLS habilitado" "ok" || check "RLS ausente em: $MISSING_RLS" "fail"

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
  [ -z "$(echo "$MISSING_POLICIES" | tr -d '[:space:]')" ] && check "Policies criticas" "ok" || check "Policies ausentes: $MISSING_POLICIES" "fail"

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
  [ -z "$(echo "$MISSING_TRIGGERS" | tr -d '[:space:]')" ] && check "Triggers criticos" "ok" || check "Triggers ausentes: $MISSING_TRIGGERS" "fail"
fi

# ==============================================================
# SEÇÃO 5 - Storage buckets
# ==============================================================
echo -e "\n${BLUE}5. Storage${NC}"
BUCKETS=$(run_sql "SELECT count(*) FROM storage.buckets WHERE id IN ('property-media','contract-documents','tenant-documents','inspection-media','sales-documents');")
[ "${BUCKETS:-0}" -eq 5 ] && check "Buckets obrigatorios (5/5)" "ok" || check "Buckets obrigatorios (${BUCKETS:-0}/5)" "fail"

STORAGE_POLICIES=$(run_sql "SELECT count(*) FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname IN (
'Admins can upload contract-documents','Admins can read contract-documents','Admins can update contract-documents','Admins can delete contract-documents',
'Admins can upload tenant-documents','Admins can read tenant-documents','Admins can update tenant-documents','Admins can delete tenant-documents',
'Admins can upload inspection-media','Admins can read inspection-media','Admins can update inspection-media','Admins can delete inspection-media',
'Admins can upload sales-documents','Admins can read sales-documents','Admins can update sales-documents','Admins can delete sales-documents',
'Admins can upload property-media','Admins can update property-media','Admins can delete property-media','Public can read property-media',
'Service role can manage contract-documents','Service role can manage tenant-documents','Service role can manage inspection-media','Service role can manage sales-documents','Service role can manage property-media');")
[ "${STORAGE_POLICIES:-0}" -ge 25 ] && check "Policies storage (${STORAGE_POLICIES}/25)" "ok" || check "Policies storage (${STORAGE_POLICIES:-0}/25)" "fail"

SERVICE_ROLE_BYPASS=$(run_sql "SELECT CASE WHEN rolbypassrls THEN 'ok' ELSE 'fail' END FROM pg_roles WHERE rolname='service_role';")
[ "$SERVICE_ROLE_BYPASS" = "ok" ] && check "service_role com BYPASSRLS" "ok" || check "service_role sem BYPASSRLS" "fail"

STORAGE_ADMIN_BYPASS=$(run_sql "SELECT CASE WHEN rolbypassrls THEN 'ok' ELSE 'fail' END FROM pg_roles WHERE rolname='supabase_storage_admin';")
[ "$STORAGE_ADMIN_BYPASS" = "ok" ] && check "supabase_storage_admin com BYPASSRLS" "ok" || check "supabase_storage_admin sem BYPASSRLS" "fail"

STORAGE_ADMIN_SERVICE_ROLE=$(run_sql "SELECT CASE WHEN pg_has_role('supabase_storage_admin', 'service_role', 'MEMBER') THEN 'ok' ELSE 'fail' END;")
[ "$STORAGE_ADMIN_SERVICE_ROLE" = "ok" ] && check "supabase_storage_admin membro de service_role" "ok" || check "supabase_storage_admin sem grant de service_role" "fail"

SERVICE_ROLE_JWT_STATUS="$(validate_jwt_role "$SERVICE_ROLE_KEY" "service_role" 2>/dev/null || echo "invalid")"
[ "$SERVICE_ROLE_JWT_STATUS" = "ok" ] && check "SERVICE_ROLE_KEY assinado pelo JWT_SECRET com role=service_role" "ok" || check "SERVICE_ROLE_KEY inválida (${SERVICE_ROLE_JWT_STATUS})" "fail"

STORAGE_GRANTS_OK=$(run_sql "
SELECT CASE WHEN
  has_schema_privilege('authenticated', 'storage', 'USAGE')
  AND has_schema_privilege('service_role', 'storage', 'USAGE')
  AND has_table_privilege('anon', 'storage.objects', 'SELECT')
  AND has_table_privilege('authenticated', 'storage.objects', 'SELECT')
  AND has_table_privilege('authenticated', 'storage.objects', 'INSERT')
  AND has_table_privilege('authenticated', 'storage.objects', 'UPDATE')
  AND has_table_privilege('authenticated', 'storage.objects', 'DELETE')
  AND has_table_privilege('service_role', 'storage.objects', 'SELECT')
  AND has_table_privilege('service_role', 'storage.objects', 'INSERT')
  AND has_table_privilege('service_role', 'storage.objects', 'UPDATE')
  AND has_table_privilege('service_role', 'storage.objects', 'DELETE')
  AND has_table_privilege('authenticated', 'storage.buckets', 'SELECT')
  AND has_table_privilege('service_role', 'storage.buckets', 'SELECT')
THEN 'ok' ELSE 'fail' END;")
[ "$STORAGE_GRANTS_OK" = "ok" ] && check "Grants em storage.objects/buckets para authenticated + service_role" "ok" || check "Grants ausentes em storage.objects/buckets para authenticated + service_role" "fail"

SMOKE_PATH="__healthchecks__/validate-install.txt"
SMOKE_PAYLOAD="storage-smoke $(date -u +%Y-%m-%dT%H:%M:%SZ)"
STORAGE_UPLOAD_HTTP=$(printf "%s" "$SMOKE_PAYLOAD" | curl -sS -m 20 -o /tmp/simply-storage-smoke.json -w "%{http_code}" \
  -X POST "http://127.0.0.1:${KONG_PORT}/storage/v1/object/property-media/${SMOKE_PATH}" \
  -H "apikey: ${SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" \
  -H "Content-Type: text/plain" \
  -H "x-upsert: true" \
  --data-binary @- 2>/dev/null || echo "000")

case "$STORAGE_UPLOAD_HTTP" in
  200|201)
    check "Storage upload real com SERVICE_ROLE_KEY (HTTP $STORAGE_UPLOAD_HTTP)" "ok"
    ;;
  *)
    STORAGE_UPLOAD_BODY=$(tr '\n' ' ' < /tmp/simply-storage-smoke.json 2>/dev/null | sed 's/  */ /g' | cut -c1-220)
    check "Storage upload real com SERVICE_ROLE_KEY (HTTP $STORAGE_UPLOAD_HTTP) ${STORAGE_UPLOAD_BODY}" "fail"
    ;;
esac

# ==============================================================
# SEÇÃO 6 - Exposição pública (opcional, com --public)
# ==============================================================
echo -e "\n${BLUE}6. Exposição pública${NC}"
if [ "$CHECK_PUBLIC" = "true" ] && [ -n "$SITE_DOMAIN" ]; then
  echo -e "   ${CYAN}Verificando dominio: ${SITE_DOMAIN}${NC}"

  # Verificar se nginx do host tem config para este domínio
  NGINX_HAS_CONF=false
  if command -v nginx &>/dev/null; then
    if nginx -T 2>/dev/null | grep -q "server_name.*${SITE_DOMAIN}"; then
      check "Nginx do host tem config para ${SITE_DOMAIN}" "ok"
      NGINX_HAS_CONF=true
    else
      check "Nginx do host NAO tem config para ${SITE_DOMAIN}" "fail"
      echo -e "   ${YELLOW}→ O nginx do host não está configurado para este domínio.${NC}"
      echo -e "   ${YELLOW}→ Copie nginx-site.conf para /etc/nginx/sites-available/ e ative.${NC}"
    fi
  else
    check "Nginx nao instalado no host" "warn"
  fi

  # Verificar se nginx do host faz proxy para a porta correta
  if [ "$NGINX_HAS_CONF" = "true" ]; then
    if nginx -T 2>/dev/null | grep -q "proxy_pass.*127.0.0.1:${FRONTEND_PORT}"; then
      check "Nginx proxy → 127.0.0.1:${FRONTEND_PORT}" "ok"
    else
      check "Nginx proxy NAO aponta para 127.0.0.1:${FRONTEND_PORT}" "fail"
    fi
  fi

  # Verificar se URL pública responde com conteúdo deste projeto
  PUB_ST=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" "https://${SITE_DOMAIN}/" 2>/dev/null || echo "000")
  PUB_BODY=$(curl -sS -m 10 "https://${SITE_DOMAIN}/" 2>/dev/null | head -50 || echo "")

  if [ "$PUB_ST" = "200" ]; then
    if echo "$PUB_BODY" | grep -qi "simply\|imoveis\|simplyimoveis"; then
      check "URL publica https://${SITE_DOMAIN} (HTTP $PUB_ST, conteudo correto)" "ok"
    else
      check "URL publica https://${SITE_DOMAIN} (HTTP $PUB_ST, CONTEUDO DE OUTRO SISTEMA)" "fail"
      echo -e "   ${RED}→ A URL pública está respondendo, mas com conteúdo de outro sistema!${NC}"
      echo -e "   ${RED}→ O nginx do host provavelmente aponta para outro container/app.${NC}"
    fi
  elif [ "$PUB_ST" = "000" ]; then
    check "URL publica https://${SITE_DOMAIN} (sem resposta)" "warn"
    echo -e "   ${YELLOW}→ DNS pode não estar apontando para este servidor.${NC}"
  else
    check "URL publica https://${SITE_DOMAIN} (HTTP $PUB_ST)" "warn"
  fi
else
  echo -e "   ${YELLOW}⊘ Verificação pública pulada.${NC}"
  echo -e "   ${YELLOW}  Use: bash validate-install.sh --public${NC}"
  echo -e "   ${YELLOW}  A publicação depende da configuração do nginx do host.${NC}"
fi

# ==============================================================
# RESUMO
# ==============================================================
echo ""
echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Resumo${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
echo -e "   ${GREEN}Passed: $PASS${NC}  ${YELLOW}Warnings: $WARN${NC}  ${RED}Failed: $FAIL${NC}"
echo ""
echo -e "${CYAN}  Endpoints internos (sempre disponíveis):${NC}"
echo -e "    Frontend:  http://127.0.0.1:${FRONTEND_PORT}"
echo -e "    Gateway:   http://127.0.0.1:${KONG_PORT}"
echo -e "    Banco:     127.0.0.1:5432"
echo ""
if [ -n "$SITE_DOMAIN" ]; then
  echo -e "${CYAN}  Endpoint público (requer nginx do host):${NC}"
  echo -e "    https://${SITE_DOMAIN}"
  echo -e "    ${YELLOW}Status: depende da configuração do nginx do host${NC}"
fi
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}Validação falhou com $FAIL erro(s) crítico(s).${NC}"
  echo -e "${YELLOW}Debug:${NC}"
  echo -e "   cd $SCRIPT_DIR && docker compose logs --tail=120 db rest auth storage kong functions"
  exit 1
fi

echo -e "${GREEN}Stack interno validado com sucesso!${NC}"
if [ "$CHECK_PUBLIC" != "true" ]; then
  echo -e "${YELLOW}NOTA: A exposição pública NÃO foi validada.${NC}"
  echo -e "${YELLOW}      Rode: bash validate-install.sh --public${NC}"
fi
exit 0
