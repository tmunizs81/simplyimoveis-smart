#!/bin/bash
# ============================================================
# Simply Imóveis - Atualização RÁPIDA (incremental)
# Atualiza código, frontend e functions SEM reinstalar tudo.
# Preserva banco, storage, .env e dados existentes.
#
# Uso: cd /opt/simply-imoveis/docker && sudo bash quick-update.sh
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$SCRIPT_DIR"
[ ! -f .env ] && echo -e "${RED}❌ .env não encontrado em $SCRIPT_DIR${NC}" && exit 1

echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Simply Imóveis — Atualização Rápida              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"

# ── 1. Backup do .env (segurança) ──
ENV_BACKUP="/tmp/simply-env-$(date +%Y%m%d-%H%M%S)"
cp .env "$ENV_BACKUP"
echo -e "   ${GREEN}✅ .env backup: $ENV_BACKUP${NC}"

# ── 2. Pull do código ──
echo -e "\n${BLUE}1️⃣  Atualizando código do GitHub...${NC}"
cd "$INSTALL_DIR"
if [ -d ".git" ]; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
  git fetch --all --prune 2>/dev/null
  git reset --hard "origin/$BRANCH" 2>/dev/null
  echo -e "   ${GREEN}✅ Código atualizado (branch: $BRANCH)${NC}"
else
  echo -e "   ${YELLOW}⚠️  Sem repositório git. Pulando pull.${NC}"
fi

# ── Restaurar .env (git reset pode sobrescrever) ──
cp "$ENV_BACKUP" "$SCRIPT_DIR/.env"

# ── Permissões ──
cd "$SCRIPT_DIR"
chmod +x *.sh 2>/dev/null || true
chmod +x volumes/db/init/*.sh 2>/dev/null || true

# ── 3. Sync Edge Functions ──
echo -e "\n${BLUE}2️⃣  Sincronizando Edge Functions...${NC}"
bash sync-functions.sh "$INSTALL_DIR/supabase/functions" "volumes/functions"
bash render-kong-config.sh
echo -e "   ${GREEN}✅ Functions e Kong sincronizados${NC}"

# ── 4. Rebuild frontend ──
echo -e "\n${BLUE}3️⃣  Rebuild do frontend...${NC}"
docker compose build --no-cache frontend
echo -e "   ${GREEN}✅ Frontend compilado${NC}"

# ── 5. Restart serviços afetados (SEM tocar no DB) ──
echo -e "\n${BLUE}4️⃣  Reiniciando serviços...${NC}"
docker compose up -d frontend
docker compose up -d --force-recreate functions kong
echo -e "   ${GREEN}✅ Frontend + Functions + Kong reiniciados${NC}"

# ── 6. Aguardar e validar ──
echo -e "\n${BLUE}5️⃣  Aguardando serviços (10s)...${NC}"
sleep 10

read_env() { grep -E "^${1}=" "$SCRIPT_DIR/.env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"; }
KONG_HTTP_PORT=$(read_env "KONG_HTTP_PORT"); KONG_HTTP_PORT="${KONG_HTTP_PORT:-8000}"
ANON_KEY=$(read_env "ANON_KEY")
FRONTEND_PORT=$(read_env "FRONTEND_PORT"); FRONTEND_PORT="${FRONTEND_PORT:-3000}"

ERRORS=0

# Testar frontend
FE_ST=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${FRONTEND_PORT}/" 2>/dev/null || echo "000")
if [ "$FE_ST" = "200" ]; then
  echo -e "   ${GREEN}✅ Frontend: HTTP $FE_ST${NC}"
else
  echo -e "   ${RED}❌ Frontend: HTTP $FE_ST${NC}"; ERRORS=$((ERRORS + 1))
fi

# Testar Auth
AUTH_ST=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${KONG_HTTP_PORT}/auth/v1/settings" -H "apikey: ${ANON_KEY}" 2>/dev/null || echo "000")
if [ "$AUTH_ST" = "200" ]; then
  echo -e "   ${GREEN}✅ Auth: HTTP $AUTH_ST${NC}"
else
  echo -e "   ${YELLOW}⚠️  Auth: HTTP $AUTH_ST${NC}"; ERRORS=$((ERRORS + 1))
fi

# Testar Functions
FUNC_ST=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${KONG_HTTP_PORT}/functions/v1/" -H "apikey: ${ANON_KEY}" 2>/dev/null || echo "000")
if [ "$FUNC_ST" = "200" ]; then
  echo -e "   ${GREEN}✅ Functions: HTTP $FUNC_ST${NC}"
else
  echo -e "   ${YELLOW}⚠️  Functions: HTTP $FUNC_ST (pode ser normal)${NC}"
fi

# Testar REST
REST_ST=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${KONG_HTTP_PORT}/rest/v1/" -H "apikey: ${ANON_KEY}" 2>/dev/null || echo "000")
if [ "$REST_ST" = "200" ]; then
  echo -e "   ${GREEN}✅ REST API: HTTP $REST_ST${NC}"
else
  echo -e "   ${YELLOW}⚠️  REST API: HTTP $REST_ST${NC}"
fi

echo ""
if [ "$ERRORS" -eq 0 ]; then
  echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║  ✅ Atualização rápida concluída com sucesso!        ║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
else
  echo -e "${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${YELLOW}║  ⚠️  Atualização concluída com $ERRORS alerta(s)       ║${NC}"
  echo -e "${YELLOW}║  Tente: docker compose restart auth rest storage    ║${NC}"
  echo -e "${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
fi
