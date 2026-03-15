#!/bin/bash
# ============================================================
# Simply Imóveis - Diagnóstico completo do stack self-hosted
# Uso: bash health-check.sh [--fix]
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'
ERRORS=0; WARNINGS=0

AUTO_FIX=false
[[ "${1:-}" == "--fix" ]] && AUTO_FIX=true

ok()   { echo -e "  ${GREEN}✅ $1${NC}"; }
warn() { echo -e "  ${YELLOW}⚠️  $1${NC}"; WARNINGS=$((WARNINGS + 1)); }
fail() { echo -e "  ${RED}❌ $1${NC}"; ERRORS=$((ERRORS + 1)); }

echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Simply Imóveis — Health Check${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"

# ── .env ──
echo -e "\n${CYAN}[1/9] Arquivo .env${NC}"
if [ ! -f .env ]; then
  fail ".env não encontrado em $SCRIPT_DIR"
  echo -e "${RED}Abortando — crie o .env a partir do .env.example${NC}"
  exit 1
fi
ok ".env encontrado"

read_env() { grep -E "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"; }

JWT_SECRET=$(read_env "JWT_SECRET")
POSTGRES_PASSWORD=$(read_env "POSTGRES_PASSWORD")
ANON_KEY=$(read_env "ANON_KEY")
SERVICE_ROLE_KEY=$(read_env "SERVICE_ROLE_KEY")
SITE_DOMAIN=$(read_env "SITE_DOMAIN")
KONG_PORT=$(read_env "KONG_HTTP_PORT"); KONG_PORT="${KONG_PORT:-8000}"
FRONTEND_PORT=$(read_env "FRONTEND_PORT"); FRONTEND_PORT="${FRONTEND_PORT:-3000}"

for var in JWT_SECRET POSTGRES_PASSWORD ANON_KEY SERVICE_ROLE_KEY SITE_DOMAIN; do
  val=$(read_env "$var")
  if [ -z "$val" ] || [ "$val" = "CHANGE_ME" ]; then
    fail "$var está vazio ou com valor padrão"
  else
    ok "$var configurado"
  fi
done

# ── System Resources ──
echo -e "\n${CYAN}[2/9] Recursos do Sistema${NC}"
RAM_MB=$(free -m 2>/dev/null | awk '/Mem:/{print $2}' || echo "0")
DISK_GB=$(df -BG / 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G' || echo "0")
CPU=$(nproc 2>/dev/null || echo "1")
[ "$RAM_MB" -ge 2000 ] && ok "RAM: ${RAM_MB}MB" || warn "RAM: ${RAM_MB}MB (recomendado 2GB+)"
[ "${DISK_GB:-0}" -ge 5 ] && ok "Disco: ${DISK_GB}GB livres" || warn "Disco: ${DISK_GB}GB livres (recomendado 5GB+)"
ok "CPU: ${CPU} cores"

# ── Containers ──
echo -e "\n${CYAN}[3/9] Containers Docker${NC}"
CONTAINERS="simply-db simply-auth simply-rest simply-storage simply-kong simply-functions simply-frontend"
FAILED_CONTAINERS=""
for c in $CONTAINERS; do
  STATUS=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo "not_found")
  RESTARTING=$(docker inspect -f '{{.State.Restarting}}' "$c" 2>/dev/null || echo "false")
  if [ "$STATUS" = "running" ] && [ "$RESTARTING" != "true" ]; then
    ok "$c: running"
  else
    fail "$c: $STATUS"
    FAILED_CONTAINERS="$FAILED_CONTAINERS $c"
  fi
done

if [ -n "$FAILED_CONTAINERS" ] && [ "$AUTO_FIX" = "true" ]; then
  echo -e "  ${YELLOW}Tentando reiniciar containers falhando...${NC}"
  docker compose up -d --force-recreate $FAILED_CONTAINERS 2>/dev/null || true
  sleep 10
fi

# ── PostgreSQL ──
echo -e "\n${CYAN}[4/9] PostgreSQL${NC}"
DB_NAME=$(read_env "POSTGRES_DB"); DB_NAME="${DB_NAME:-simply_db}"
DB_RESULT=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" simply-db \
  psql -tA -w -h 127.0.0.1 -U supabase_admin -d "$DB_NAME" -c "SELECT 1" 2>/dev/null || echo "FAIL")
if [ "$DB_RESULT" = "1" ]; then
  ok "Conexão PostgreSQL OK"
else
  fail "Não foi possível conectar ao PostgreSQL"
fi

for tbl in user_roles properties contact_submissions tenants rental_contracts sales financial_transactions; do
  EXISTS=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" simply-db \
    psql -tA -w -h 127.0.0.1 -U supabase_admin -d "$DB_NAME" \
    -c "SELECT to_regclass('public.$tbl') IS NOT NULL;" 2>/dev/null | tr -d '[:space:]' || echo "f")
  [ "$EXISTS" = "t" ] && ok "Tabela public.$tbl" || fail "Tabela public.$tbl NÃO existe"
done

AUTH_USERS=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" simply-db \
  psql -tA -w -h 127.0.0.1 -U supabase_admin -d "$DB_NAME" \
  -c "SELECT to_regclass('auth.users') IS NOT NULL;" 2>/dev/null | tr -d '[:space:]' || echo "f")
[ "$AUTH_USERS" = "t" ] && ok "auth.users existe (GoTrue migrou)" || fail "auth.users NÃO existe"

# ── JWT Consistency ──
echo -e "\n${CYAN}[5/9] Consistência JWT${NC}"
ANON_PAYLOAD=$(echo "$ANON_KEY" | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null || echo "{}")
ANON_ROLE=$(echo "$ANON_PAYLOAD" | grep -o '"role":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
[ "$ANON_ROLE" = "anon" ] && ok "ANON_KEY role=anon" || fail "ANON_KEY role='$ANON_ROLE' (esperado 'anon')"

SRK_PAYLOAD=$(echo "$SERVICE_ROLE_KEY" | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null || echo "{}")
SRK_ROLE=$(echo "$SRK_PAYLOAD" | grep -o '"role":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
[ "$SRK_ROLE" = "service_role" ] && ok "SERVICE_ROLE_KEY role=service_role" || fail "SERVICE_ROLE_KEY role='$SRK_ROLE'"

# ── Kong API Gateway ──
echo -e "\n${CYAN}[6/9] Kong API Gateway${NC}"
KONG_HTTP=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" "http://127.0.0.1:${KONG_PORT}/" 2>/dev/null || echo "000")
[ "$KONG_HTTP" != "000" ] && ok "Kong porta $KONG_PORT (HTTP $KONG_HTTP)" || fail "Kong não respondendo na porta $KONG_PORT"

if [ -f volumes/kong/kong.yml ]; then
  grep -q "${ANON_KEY:0:30}" volumes/kong/kong.yml 2>/dev/null && ok "kong.yml contém ANON_KEY atual" || fail "kong.yml desatualizado — rode: bash render-kong-config.sh"
else
  fail "volumes/kong/kong.yml não encontrado"
fi

if [ "$AUTO_FIX" = "true" ] && ! grep -q "${ANON_KEY:0:30}" volumes/kong/kong.yml 2>/dev/null; then
  bash render-kong-config.sh 2>/dev/null && docker compose restart kong 2>/dev/null && echo -e "  ${GREEN}Kong reconfigurado automaticamente${NC}" || true
fi

# ── GoTrue Auth ──
echo -e "\n${CYAN}[7/9] GoTrue (Auth)${NC}"
AUTH_HTTP=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" "http://127.0.0.1:${KONG_PORT}/auth/v1/settings" -H "apikey: ${ANON_KEY}" 2>/dev/null || echo "000")
[ "$AUTH_HTTP" = "200" ] && ok "Auth /settings (HTTP 200)" || fail "Auth /settings (HTTP $AUTH_HTTP)"

ADMIN_HTTP=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" \
  -H "apikey: ${SERVICE_ROLE_KEY}" -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" \
  "http://127.0.0.1:${KONG_PORT}/auth/v1/admin/users?per_page=1" 2>/dev/null || echo "000")
[ "$ADMIN_HTTP" = "200" ] && ok "Auth Admin API (HTTP 200)" || fail "Auth Admin API (HTTP $ADMIN_HTTP)"

# ── PostgREST + Functions ──
echo -e "\n${CYAN}[8/9] PostgREST + Edge Functions${NC}"
REST_HTTP=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" "http://127.0.0.1:${KONG_PORT}/rest/v1/properties?select=id&limit=1" -H "apikey: ${ANON_KEY}" 2>/dev/null || echo "000")
[ "$REST_HTTP" = "200" ] && ok "PostgREST (HTTP 200)" || fail "PostgREST (HTTP $REST_HTTP)"

FN_HTTP=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" -X OPTIONS "http://127.0.0.1:${KONG_PORT}/functions/v1/admin-crud" -H "apikey: ${ANON_KEY}" 2>/dev/null || echo "000")
case "$FN_HTTP" in 200|204) ok "Edge Functions (CORS OK)" ;; *) fail "Edge Functions (HTTP $FN_HTTP)" ;; esac

[ -f volumes/functions/main/index.ts ] && ok "main/index.ts existe" || fail "main/index.ts ausente — rode: bash sync-functions.sh"

if [ "$AUTO_FIX" = "true" ] && [ ! -f volumes/functions/main/index.ts ]; then
  bash sync-functions.sh 2>/dev/null && docker compose restart functions 2>/dev/null && echo -e "  ${GREEN}Functions resincronizadas automaticamente${NC}" || true
fi

# ── Frontend + Admin ──
echo -e "\n${CYAN}[9/9] Frontend + Admin${NC}"
FE_HTTP=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" "http://127.0.0.1:${FRONTEND_PORT}/" 2>/dev/null || echo "000")
[ "$FE_HTTP" = "200" ] && ok "Frontend (HTTP 200)" || warn "Frontend (HTTP $FE_HTTP)"

if [ "$AUTH_USERS" = "t" ]; then
  ADMIN_COUNT=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" simply-db \
    psql -tA -w -h 127.0.0.1 -U supabase_admin -d "$DB_NAME" \
    -c "SELECT count(*) FROM public.user_roles WHERE role='admin';" 2>/dev/null | tr -d '[:space:]' || echo "0")
  [ "$ADMIN_COUNT" -gt 0 ] 2>/dev/null && ok "$ADMIN_COUNT admin(s) cadastrado(s)" || warn "Nenhum admin — rode: bash create-admin.sh email senha"
fi

# ── Resultado ──
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
if [ "$ERRORS" -eq 0 ]; then
  echo -e "${GREEN}  ✅ Tudo OK — 0 erros, $WARNINGS alerta(s)${NC}"
else
  echo -e "${RED}  ❌ $ERRORS erro(s), $WARNINGS alerta(s)${NC}"
  echo ""
  echo -e "${YELLOW}  Comandos para correção:${NC}"
  echo -e "${YELLOW}    bash health-check.sh --fix             — tentar auto-correção${NC}"
  echo -e "${YELLOW}    bash fix-auth-keys.sh email senha       — regenerar JWT/admin${NC}"
  echo -e "${YELLOW}    bash sync-db-passwords.sh               — sincronizar grants${NC}"
  echo -e "${YELLOW}    bash render-kong-config.sh               — atualizar kong.yml${NC}"
  echo -e "${YELLOW}    bash sync-functions.sh                   — sincronizar functions${NC}"
  echo -e "${YELLOW}    docker compose logs --tail=50 auth       — logs do GoTrue${NC}"
fi
echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"

exit $ERRORS
