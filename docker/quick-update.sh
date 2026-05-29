#!/bin/bash
# ============================================================
# Simply Imóveis - Atualização RÁPIDA (incremental)
# Baixa código do GitHub (tarball), rebuild frontend + functions.
# Preserva banco, storage, .env e dados existentes.
#
# Uso: cd /opt/simply-imoveis/docker && sudo bash quick-update.sh
#      sudo bash quick-update.sh --repo https://github.com/user/repo
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$SCRIPT_DIR"
[ ! -f .env ] && echo -e "${RED}❌ .env não encontrado em $SCRIPT_DIR${NC}" && exit 1

read_env() { grep -E "^${1}=" "$SCRIPT_DIR/.env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"; }

echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Simply Imóveis — Atualização Rápida              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"

# ── 1. Backup do .env ──
ENV_BACKUP="/tmp/simply-env-$(date +%Y%m%d-%H%M%S)"
cp .env "$ENV_BACKUP"
echo -e "   ${GREEN}✅ .env backup: $ENV_BACKUP${NC}"

# ── 2. Baixar código do GitHub ──
echo -e "\n${BLUE}1️⃣  Baixando código do GitHub...${NC}"

# Detectar repo: flag --repo > .env GITHUB_REPO > git remote > perguntar
REPO_URL=""
for arg in "$@"; do
  case "$arg" in --repo) shift; REPO_URL="${1:-}"; shift || true ;; --repo=*) REPO_URL="${arg#*=}" ;; esac
done
[ -z "$REPO_URL" ] && REPO_URL=$(read_env "GITHUB_REPO")
[ -z "$REPO_URL" ] && [ -d "$INSTALL_DIR/.git" ] && REPO_URL=$(cd "$INSTALL_DIR" && git remote get-url origin 2>/dev/null || true)
[ -z "$REPO_URL" ] && read -p "   URL do repositório GitHub: " REPO_URL
[ -z "$REPO_URL" ] && echo -e "${RED}❌ URL não informada${NC}" && exit 1

# Normalizar URL para tarball
REPO_URL="${REPO_URL%.git}"
BRANCH="${BRANCH:-main}"
TARBALL_URL="${REPO_URL}/archive/refs/heads/${BRANCH}.tar.gz"

TMP_DIR=$(mktemp -d)
echo -e "   Baixando ${TARBALL_URL}..."
if ! curl -fsSL "$TARBALL_URL" -o "$TMP_DIR/repo.tar.gz" 2>/dev/null; then
  # Tentar branch master
  BRANCH="master"
  TARBALL_URL="${REPO_URL}/archive/refs/heads/${BRANCH}.tar.gz"
  echo -e "   ${YELLOW}Branch main não encontrada, tentando master...${NC}"
  curl -fsSL "$TARBALL_URL" -o "$TMP_DIR/repo.tar.gz" || { echo -e "${RED}❌ Falha ao baixar do GitHub${NC}"; rm -rf "$TMP_DIR"; exit 1; }
fi

# Extrair (o tarball cria uma pasta repo-branch/)
tar -xzf "$TMP_DIR/repo.tar.gz" -C "$TMP_DIR"
EXTRACTED=$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)

# Copiar tudo EXCETO docker/.env (preservar configs)
rsync -a --exclude='docker/.env' --exclude='node_modules' "$EXTRACTED/" "$INSTALL_DIR/"
rm -rf "$TMP_DIR"

echo -e "   ${GREEN}✅ Código atualizado (branch: $BRANCH)${NC}"

# ── Restaurar .env (segurança extra) ──
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

# ── 4. Rebuild + restart via docker compose ──
echo -e "\n${BLUE}3️⃣  Docker Compose: rebuild + restart...${NC}"
docker compose build --no-cache frontend
docker compose up -d frontend
docker compose up -d --force-recreate functions kong
echo -e "   ${GREEN}✅ Frontend + Functions + Kong reiniciados${NC}"

# ── 5. Validar ──
echo -e "\n${BLUE}4️⃣  Aguardando serviços (10s)...${NC}"
sleep 10

KONG_HTTP_PORT=$(read_env "KONG_HTTP_PORT"); KONG_HTTP_PORT="${KONG_HTTP_PORT:-8000}"
ANON_KEY=$(read_env "ANON_KEY")
FRONTEND_PORT=$(read_env "FRONTEND_PORT"); FRONTEND_PORT="${FRONTEND_PORT:-3000}"

ERRORS=0

FE_ST=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${FRONTEND_PORT}/" 2>/dev/null || echo "000")
[ "$FE_ST" = "200" ] && echo -e "   ${GREEN}✅ Frontend: HTTP $FE_ST${NC}" || { echo -e "   ${RED}❌ Frontend: HTTP $FE_ST${NC}"; ERRORS=$((ERRORS + 1)); }

AUTH_ST=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${KONG_HTTP_PORT}/auth/v1/settings" -H "apikey: ${ANON_KEY}" 2>/dev/null || echo "000")
[ "$AUTH_ST" = "200" ] && echo -e "   ${GREEN}✅ Auth: HTTP $AUTH_ST${NC}" || { echo -e "   ${YELLOW}⚠️  Auth: HTTP $AUTH_ST${NC}"; ERRORS=$((ERRORS + 1)); }

FUNC_ST=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${KONG_HTTP_PORT}/functions/v1/" -H "apikey: ${ANON_KEY}" 2>/dev/null || echo "000")
[ "$FUNC_ST" = "200" ] && echo -e "   ${GREEN}✅ Functions: HTTP $FUNC_ST${NC}" || echo -e "   ${YELLOW}⚠️  Functions: HTTP $FUNC_ST (pode ser normal)${NC}"

AI_GEN_ST=$(curl -s -o /tmp/simply-ai-generate-check.json -w "%{http_code}" -X POST "http://127.0.0.1:${KONG_HTTP_PORT}/functions/v1/ai-generate" -H "apikey: ${ANON_KEY}" -H "Content-Type: application/json" -d '{}' 2>/dev/null || echo "000")
case "$AI_GEN_ST" in
  400|401|403) echo -e "   ${GREEN}✅ AI Generate: HTTP $AI_GEN_ST (endpoint registrado)${NC}" ;;
  404) echo -e "   ${RED}❌ AI Generate não registrado no router (HTTP 404). Rode: bash sync-functions.sh && docker compose up -d --force-recreate functions kong${NC}"; ERRORS=$((ERRORS + 1)) ;;
  *) echo -e "   ${YELLOW}⚠️  AI Generate: HTTP $AI_GEN_ST${NC}" ;;
esac

REST_ST=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${KONG_HTTP_PORT}/rest/v1/" -H "apikey: ${ANON_KEY}" 2>/dev/null || echo "000")
[ "$REST_ST" = "200" ] && echo -e "   ${GREEN}✅ REST API: HTTP $REST_ST${NC}" || echo -e "   ${YELLOW}⚠️  REST API: HTTP $REST_ST${NC}"

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
