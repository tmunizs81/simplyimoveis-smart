#!/bin/bash
# ============================================================
# Simply Imóveis - Diagnóstico completo do stack self-hosted
# Uso: bash health-check.sh
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'
ERRORS=0

ok()   { echo -e "  ${GREEN}✅ $1${NC}"; }
warn() { echo -e "  ${YELLOW}⚠️  $1${NC}"; }
fail() { echo -e "  ${RED}❌ $1${NC}"; ERRORS=$((ERRORS + 1)); }

echo -e "${CYAN}══════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Simply Imóveis — Health Check${NC}"
echo -e "${CYAN}══════════════════════════════════════════════${NC}"

# ── .env ──
echo -e "\n${CYAN}[1/8] Arquivo .env${NC}"
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

# ── Containers ──
echo -e "\n${CYAN}[2/8] Containers Docker${NC}"
CONTAINERS="simply-db simply-auth simply-rest simply-storage simply-kong simply-functions simply-frontend"
for c in $CONTAINERS; do
  STATUS=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo "not_found")
  if [ "$STATUS" = "running" ]; then
    ok "$c: running"
  else
    fail "$c: $STATUS"
  fi
done

# ── PostgreSQL ──
echo -e "\n${CYAN}[3/8] PostgreSQL${NC}"
DB_NAME=$(read_env "POSTGRES_DB"); DB_NAME="${DB_NAME:-simply_db}"
DB_RESULT=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" simply-db \
  psql -tA -w -h 127.0.0.1 -U supabase_admin -d "$DB_NAME" -c "SELECT 1" 2>/dev/null || echo "FAIL")
if [ "$DB_RESULT" = "1" ]; then
  ok "Conexão PostgreSQL OK"
else
  fail "Não foi possível conectar ao PostgreSQL"
fi

# Verifica tabelas essenciais
for tbl in user_roles properties contact_submissions; do
  EXISTS=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" simply-db \
    psql -tA -w -h 127.0.0.1 -U supabase_admin -d "$DB_NAME" \
    -c "SELECT to_regclass('public.$tbl') IS NOT NULL;" 2>/dev/null | tr -d '[:space:]' || echo "f")
  if [ "$EXISTS" = "t" ]; then
    ok "Tabela public.$tbl existe"
  else
    fail "Tabela public.$tbl NÃO existe"
  fi
done

# Verifica auth.users
AUTH_USERS=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" simply-db \
  psql -tA -w -h 127.0.0.1 -U supabase_admin -d "$DB_NAME" \
  -c "SELECT to_regclass('auth.users') IS NOT NULL;" 2>/dev/null | tr -d '[:space:]' || echo "f")
if [ "$AUTH_USERS" = "t" ]; then
  ok "auth.users existe (GoTrue migrou)"
else
  fail "auth.users NÃO existe — GoTrue não migrou o schema"
fi

# ── JWT Consistency ──
echo -e "\n${CYAN}[4/8] Consistência JWT${NC}"
# Decodificar o payload do ANON_KEY e verificar role
ANON_PAYLOAD=$(echo "$ANON_KEY" | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null || echo "{}")
ANON_ROLE=$(echo "$ANON_PAYLOAD" | grep -o '"role":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
if [ "$ANON_ROLE" = "anon" ]; then
  ok "ANON_KEY tem role=anon"
else
  fail "ANON_KEY tem role='$ANON_ROLE' (esperado 'anon')"
fi

SRK_PAYLOAD=$(echo "$SERVICE_ROLE_KEY" | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null || echo "{}")
SRK_ROLE=$(echo "$SRK_PAYLOAD" | grep -o '"role":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
if [ "$SRK_ROLE" = "service_role" ]; then
  ok "SERVICE_ROLE_KEY tem role=service_role"
else
  fail "SERVICE_ROLE_KEY tem role='$SRK_ROLE' (esperado 'service_role')"
fi

# ── Kong API Gateway ──
echo -e "\n${CYAN}[5/8] Kong API Gateway${NC}"
KONG_HTTP=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" \
  "http://127.0.0.1:${KONG_PORT}/" 2>/dev/null || echo "000")
if [ "$KONG_HTTP" != "000" ]; then
  ok "Kong respondendo na porta $KONG_PORT (HTTP $KONG_HTTP)"
else
  fail "Kong não respondendo na porta $KONG_PORT"
fi

# Kong config tem as chaves certas?
if [ -f volumes/kong/kong.yml ]; then
  if grep -q "${ANON_KEY:0:30}" volumes/kong/kong.yml 2>/dev/null; then
    ok "kong.yml contém ANON_KEY atual"
  else
    fail "kong.yml NÃO contém ANON_KEY atual — rode: bash render-kong-config.sh"
  fi
else
  fail "volumes/kong/kong.yml não encontrado"
fi

# ── GoTrue Auth ──
echo -e "\n${CYAN}[6/8] GoTrue (Auth)${NC}"
AUTH_HTTP=$(curl -sS -m 10 -o /tmp/hc-auth-settings.json -w "%{http_code}" \
  "http://127.0.0.1:${KONG_PORT}/auth/v1/settings" \
  -H "apikey: ${ANON_KEY}" 2>/dev/null || echo "000")
if [ "$AUTH_HTTP" = "200" ]; then
  ok "Auth /settings OK (HTTP 200)"
else
  fail "Auth /settings retornou HTTP $AUTH_HTTP"
  [ -f /tmp/hc-auth-settings.json ] && cat /tmp/hc-auth-settings.json 2>/dev/null && echo ""
fi

# Admin API
ADMIN_HTTP=$(curl -sS -m 10 -o /tmp/hc-admin-users.json -w "%{http_code}" \
  -H "apikey: ${SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" \
  "http://127.0.0.1:${KONG_PORT}/auth/v1/admin/users?per_page=1" 2>/dev/null || echo "000")
if [ "$ADMIN_HTTP" = "200" ]; then
  ok "Auth Admin API OK (HTTP 200)"
else
  fail "Auth Admin API retornou HTTP $ADMIN_HTTP — SERVICE_ROLE_KEY pode estar incorreta"
fi

# ── PostgREST ──
echo -e "\n${CYAN}[7/8] PostgREST${NC}"
REST_HTTP=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" \
  "http://127.0.0.1:${KONG_PORT}/rest/v1/properties?select=id&limit=1" \
  -H "apikey: ${ANON_KEY}" 2>/dev/null || echo "000")
if [ "$REST_HTTP" = "200" ]; then
  ok "PostgREST OK (HTTP 200)"
else
  fail "PostgREST retornou HTTP $REST_HTTP"
fi

# ── Edge Functions ──
echo -e "\n${CYAN}[8/8] Edge Functions${NC}"
# Test with OPTIONS (CORS preflight — no auth needed)
FN_HTTP=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" \
  -X OPTIONS \
  "http://127.0.0.1:${KONG_PORT}/functions/v1/admin-crud" \
  -H "apikey: ${ANON_KEY}" 2>/dev/null || echo "000")
if [ "$FN_HTTP" = "200" ] || [ "$FN_HTTP" = "204" ]; then
  ok "Edge Functions respondendo (CORS OK)"
else
  fail "Edge Functions não respondendo (HTTP $FN_HTTP)"
fi

# Verifica se main/index.ts existe
if [ -f volumes/functions/main/index.ts ]; then
  ok "volumes/functions/main/index.ts existe"
else
  fail "volumes/functions/main/index.ts ausente — rode: bash sync-functions.sh"
fi

# ── Frontend ──
echo ""
FE_HTTP=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" \
  "http://127.0.0.1:${FRONTEND_PORT}/" 2>/dev/null || echo "000")
if [ "$FE_HTTP" = "200" ]; then
  ok "Frontend OK (HTTP 200 na porta $FRONTEND_PORT)"
else
  warn "Frontend retornou HTTP $FE_HTTP na porta $FRONTEND_PORT"
fi

# ── Admin user exists? ──
echo ""
if [ "$AUTH_USERS" = "t" ]; then
  ADMIN_COUNT=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" simply-db \
    psql -tA -w -h 127.0.0.1 -U supabase_admin -d "$DB_NAME" \
    -c "SELECT count(*) FROM public.user_roles WHERE role='admin';" 2>/dev/null | tr -d '[:space:]' || echo "0")
  if [ "$ADMIN_COUNT" -gt 0 ] 2>/dev/null; then
    ok "$ADMIN_COUNT admin(s) cadastrado(s)"
  else
    warn "Nenhum admin cadastrado — rode: bash create-admin.sh email senha"
  fi
fi

# ── Resultado ──
echo ""
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
if [ "$ERRORS" -eq 0 ]; then
  echo -e "${GREEN}  ✅ Tudo OK — $ERRORS erros encontrados${NC}"
else
  echo -e "${RED}  ❌ $ERRORS erro(s) encontrado(s)${NC}"
  echo ""
  echo -e "${YELLOW}  Comandos úteis para correção:${NC}"
  echo -e "${YELLOW}    bash fix-auth-keys.sh email senha  — regenera JWT e admin${NC}"
  echo -e "${YELLOW}    bash sync-db-passwords.sh          — sincroniza grants${NC}"
  echo -e "${YELLOW}    bash render-kong-config.sh          — atualiza kong.yml${NC}"
  echo -e "${YELLOW}    bash sync-functions.sh              — sincroniza functions${NC}"
  echo -e "${YELLOW}    docker compose logs --tail=50 auth  — logs do GoTrue${NC}"
fi
echo -e "${CYAN}══════════════════════════════════════════════${NC}"

exit $ERRORS
