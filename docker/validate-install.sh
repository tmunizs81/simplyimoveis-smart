#!/bin/bash
# ============================================================
# Simply Imóveis - Validação Pós-Instalação Completa
# Uso: bash validate-install.sh
# Retorna exit 0 se OK, exit 1 se falhas críticas
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

[ ! -f .env ] && echo -e "${RED}❌ .env não encontrado em $SCRIPT_DIR${NC}" && exit 1

read_env() { grep -E "^${1}=" "$SCRIPT_DIR/.env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"; }

KONG_PORT=$(read_env "KONG_HTTP_PORT"); KONG_PORT="${KONG_PORT:-8000}"
FRONTEND_PORT=$(read_env "FRONTEND_PORT"); FRONTEND_PORT="${FRONTEND_PORT:-3000}"
ANON_KEY=$(read_env "ANON_KEY")
SERVICE_ROLE_KEY=$(read_env "SERVICE_ROLE_KEY")
POSTGRES_PASSWORD=$(read_env "POSTGRES_PASSWORD")
POSTGRES_DB=$(read_env "POSTGRES_DB"); POSTGRES_DB="${POSTGRES_DB:-simply_db}"

[ -z "$ANON_KEY" ] || [ -z "$SERVICE_ROLE_KEY" ] && echo "❌ Chaves JWT não definidas" && exit 1

PASS=0; FAIL=0; WARN=0

check() {
  local desc="$1" result="$2"
  if [ "$result" = "ok" ]; then echo -e "   ${GREEN}✅ $desc${NC}"; ((PASS++))
  elif [ "$result" = "warn" ]; then echo -e "   ${YELLOW}⚠️  $desc${NC}"; ((WARN++))
  else echo -e "   ${RED}❌ $desc${NC}"; ((FAIL++)); fi
}

run_sql() {
  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" simply-db \
    psql -tA -w -h 127.0.0.1 -U supabase_admin -d "$POSTGRES_DB" -c "$1" 2>/dev/null || echo ""
}

echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Validação Pós-Instalação v14                     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"

# ── 1. Containers ──
echo -e "\n${BLUE}1. Containers${NC}"
for c in simply-db simply-auth simply-rest simply-storage simply-kong simply-functions simply-frontend; do
  st=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo "missing")
  rs=$(docker inspect -f '{{.State.Restarting}}' "$c" 2>/dev/null || echo "false")
  if [ "$st" = "running" ] && [ "$rs" != "true" ]; then check "$c" "ok"
  else check "$c ($st)" "fail"; fi
done

# ── 2. PostgreSQL ──
echo -e "\n${BLUE}2. PostgreSQL${NC}"
DB_OK=$(run_sql "SELECT 1;")
[ "$DB_OK" = "1" ] && check "Conexão com banco" "ok" || check "Conexão com banco" "fail"

if [ "$DB_OK" = "1" ]; then
  TABLES=$(run_sql "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE';")
  [ "${TABLES:-0}" -ge 10 ] && check "Schema ($TABLES tabelas)" "ok" || check "Schema ($TABLES tabelas < 10)" "fail"

  # app_role enum
  HAS_ENUM=$(run_sql "SELECT EXISTS(SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='public' AND t.typname='app_role');")
  [ "$(echo "$HAS_ENUM" | tr -d '[:space:]')" = "t" ] && check "Enum app_role" "ok" || check "Enum app_role" "fail"

  # has_role function
  HAS_ROLE=$(run_sql "SELECT to_regprocedure('public.has_role(uuid,public.app_role)') IS NOT NULL;")
  [ "$(echo "$HAS_ROLE" | tr -d '[:space:]')" = "t" ] && check "Função has_role()" "ok" || check "Função has_role()" "fail"

  # has_role_text function
  HAS_ROLE_TEXT=$(run_sql "SELECT to_regprocedure('public.has_role_text(uuid,text)') IS NOT NULL;")
  [ "$(echo "$HAS_ROLE_TEXT" | tr -d '[:space:]')" = "t" ] && check "Função has_role_text()" "ok" || check "Função has_role_text()" "fail"

  # RLS
  for tbl in tenants leads properties user_roles; do
    RLS=$(run_sql "SELECT rowsecurity FROM pg_tables WHERE tablename='$tbl' AND schemaname='public';")
    [ "$(echo "$RLS" | tr -d '[:space:]')" = "t" ] && check "RLS em $tbl" "ok" || check "RLS em $tbl" "fail"
  done

  # Triggers
  TRIGGERS=$(run_sql "SELECT count(*) FROM information_schema.triggers WHERE trigger_schema='public';")
  [ "${TRIGGERS:-0}" -ge 3 ] && check "Triggers ($TRIGGERS)" "ok" || check "Triggers ($TRIGGERS)" "warn"

  # Buckets
  BUCKETS=$(run_sql "SELECT count(*) FROM storage.buckets WHERE id IN ('property-media','contract-documents','tenant-documents','inspection-media','sales-documents');")
  [ "${BUCKETS:-0}" -ge 5 ] && check "Buckets storage ($BUCKETS/5)" "ok" || check "Buckets storage ($BUCKETS/5)" "fail"

  # Storage policies (check 6 key ones)
  STORAGE_POLICIES=$(run_sql "SELECT count(*) FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname IN ('Admins can upload contract-documents','Admins can upload tenant-documents','Admins can upload inspection-media','Admins can upload sales-documents','Admins can upload property-media','Public can read property-media');")
  [ "${STORAGE_POLICIES:-0}" -ge 6 ] && check "Policies storage ($STORAGE_POLICIES/6)" "ok" || check "Policies storage ($STORAGE_POLICIES/6)" "fail"
fi

# ── 3. Auth ──
echo -e "\n${BLUE}3. Auth (GoTrue)${NC}"
AUTH_ST=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" "http://127.0.0.1:${KONG_PORT}/auth/v1/settings" -H "apikey: ${ANON_KEY}" 2>/dev/null || echo "000")
[ "$AUTH_ST" = "200" ] && check "Auth API" "ok" || check "Auth API (HTTP $AUTH_ST)" "fail"

# ── 4. REST ──
echo -e "\n${BLUE}4. REST (PostgREST)${NC}"
REST_ST=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" "http://127.0.0.1:${KONG_PORT}/rest/v1/" -H "apikey: ${ANON_KEY}" 2>/dev/null || echo "000")
[ "$REST_ST" = "200" ] && check "PostgREST" "ok" || check "PostgREST (HTTP $REST_ST)" "fail"

# ── 5. Storage ──
echo -e "\n${BLUE}5. Storage${NC}"
STORAGE_ST=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" "http://127.0.0.1:${KONG_PORT}/storage/v1/bucket" \
  -H "apikey: ${ANON_KEY}" -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" 2>/dev/null || echo "000")
[ "$STORAGE_ST" = "200" ] && check "Storage API" "ok" || check "Storage API (HTTP $STORAGE_ST)" "warn"

# ── 6. Functions ──
echo -e "\n${BLUE}6. Edge Functions${NC}"
FUNC_DIR="volumes/functions"
for fn in chat create-admin-user notify-telegram admin-crud; do
  fn_file="$FUNC_DIR/$fn/index.ts"
  if [ ! -f "$fn_file" ]; then check "$fn: ausente" "fail"
  elif ! grep -qE '^\s*export\s+default\s' "$fn_file"; then check "$fn: sem export default" "fail"
  else check "$fn" "ok"; fi
done
[ -f "$FUNC_DIR/main/index.ts" ] && check "Main router" "ok" || check "Main router ausente" "fail"

FUNC_LOGS=$(docker logs simply-functions --tail=80 2>&1 || true)
if echo "$FUNC_LOGS" | grep -Eqi "main worker boot error|worker boot error|boot error"; then
  check "Functions runtime: BOOT ERROR" "fail"
else
  check "Functions runtime" "ok"
fi

CRUD_ST=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" -X POST "http://127.0.0.1:${KONG_PORT}/functions/v1/admin-crud" \
  -H "apikey: ${ANON_KEY}" -H "Content-Type: application/json" -d '{}' 2>/dev/null || echo "000")
[[ "$CRUD_ST" =~ ^(401|403|400)$ ]] && check "admin-crud endpoint (HTTP $CRUD_ST)" "ok" || check "admin-crud endpoint (HTTP $CRUD_ST)" "warn"

# ── 7. Frontend ──
echo -e "\n${BLUE}7. Frontend${NC}"
FE_ST=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" "http://127.0.0.1:${FRONTEND_PORT}/" 2>/dev/null || echo "000")
[ "$FE_ST" = "200" ] && check "Frontend" "ok" || check "Frontend (HTTP $FE_ST)" "fail"

# ── 8. Env vars ──
echo -e "\n${BLUE}8. Variáveis${NC}"
for var in SITE_DOMAIN JWT_SECRET POSTGRES_PASSWORD ANON_KEY SERVICE_ROLE_KEY; do
  val=$(read_env "$var"); [ -n "$val" ] && [ "$val" != "CHANGE_ME" ] && check "$var" "ok" || check "$var" "fail"
done
for var in GROQ_API_KEY TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID; do
  val=$(read_env "$var"); [ -n "$val" ] && [ "$val" != "gsk_XXXXXXXXXXXXXXXXXXXX" ] && check "$var" "ok" || check "$var (opcional)" "warn"
done

# ── 9. Arquivos do instalador ──
echo -e "\n${BLUE}9. Arquivos${NC}"
for f in sql/selfhosted-admin-recovery.sql sql/bootstrap-storage.sql bootstrap-db.sh ensure-storage-buckets.sh sync-db-passwords.sh; do
  [ -f "$SCRIPT_DIR/$f" ] && check "$f" "ok" || check "$f ausente" "fail"
done

# ── Resumo ──
echo ""
echo -e "${BLUE}════ Resumo ════${NC}"
echo -e "   ${GREEN}Passed: $PASS${NC}  ${YELLOW}Warnings: $WARN${NC}  ${RED}Failed: $FAIL${NC}"

if [ "$FAIL" -gt 0 ]; then
  echo -e "\n${RED}❌ Validação falhou ($FAIL erros)${NC}"
  echo -e "${YELLOW}Debug: docker compose logs --tail=50${NC}"
  exit 1
fi

echo -e "\n${GREEN}✅ Validação concluída!${NC}"
exit 0
