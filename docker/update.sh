#!/bin/bash
# ============================================================
# Simply Imóveis - Atualização segura do sistema
# Faz backup, baixa código, rebuild e revalida
# Uso: sudo bash update.sh [--repo URL] [--branch BRANCH]
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/simply-imoveis"

cd "$SCRIPT_DIR"
[ ! -f .env ] && echo -e "${RED}❌ .env não encontrado${NC}" && exit 1

read_env() { grep -E "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"; }

# Parse args
REPO_URL=""
BRANCH="main"
for arg in "$@"; do
  case "$arg" in
    --repo) shift; REPO_URL="${1:-}" ;;
    --repo=*) REPO_URL="${arg#*=}" ;;
    --branch) shift; BRANCH="${1:-main}" ;;
    --branch=*) BRANCH="${arg#*=}" ;;
  esac
done

echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Simply Imóveis — Atualização do Sistema          ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"

# ── 1. Backup ──
echo -e "\n${BLUE}1️⃣  Backup pré-atualização...${NC}"
bash backup.sh --db-only 2>/dev/null && echo -e "   ${GREEN}✅ Backup concluído${NC}" || echo -e "   ${YELLOW}⚠️  Backup falhou (continuando)${NC}"

# ── 2. Backup .env ──
ENV_BACKUP="/tmp/simply-env-$(date +%Y%m%d-%H%M%S)"
cp .env "$ENV_BACKUP"
echo -e "   ${GREEN}✅ .env backup: $ENV_BACKUP${NC}"

# ── 3. Baixar código ──
echo -e "\n${BLUE}2️⃣  Baixando código atualizado...${NC}"

# Detectar repo
[ -z "$REPO_URL" ] && REPO_URL=$(read_env "GITHUB_REPO")
[ -z "$REPO_URL" ] && [ -d "$INSTALL_DIR/.git" ] && REPO_URL=$(cd "$INSTALL_DIR" && git remote get-url origin 2>/dev/null || true)

if [ -n "$REPO_URL" ]; then
  REPO_URL="${REPO_URL%.git}"
  TARBALL_URL="${REPO_URL}/archive/refs/heads/${BRANCH}.tar.gz"

  TMP_DIR=$(mktemp -d)
  if curl -fsSL "$TARBALL_URL" -o "$TMP_DIR/repo.tar.gz" 2>/dev/null; then
    tar -xzf "$TMP_DIR/repo.tar.gz" -C "$TMP_DIR"
    EXTRACTED=$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)
    rsync -a --exclude='docker/.env' --exclude='node_modules' --exclude='.git' "$EXTRACTED/" "$INSTALL_DIR/"
    echo -e "   ${GREEN}✅ Código atualizado (branch: $BRANCH)${NC}"
  else
    # Tentar branch master
    TARBALL_URL="${REPO_URL}/archive/refs/heads/master.tar.gz"
    if curl -fsSL "$TARBALL_URL" -o "$TMP_DIR/repo.tar.gz" 2>/dev/null; then
      tar -xzf "$TMP_DIR/repo.tar.gz" -C "$TMP_DIR"
      EXTRACTED=$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)
      rsync -a --exclude='docker/.env' --exclude='node_modules' --exclude='.git' "$EXTRACTED/" "$INSTALL_DIR/"
      echo -e "   ${GREEN}✅ Código atualizado (branch: master)${NC}"
    else
      echo -e "   ${RED}❌ Falha ao baixar do GitHub${NC}"
      rm -rf "$TMP_DIR"
      exit 1
    fi
  fi
  rm -rf "$TMP_DIR"
elif [ -d "$INSTALL_DIR/.git" ]; then
  cd "$INSTALL_DIR"
  git fetch origin >> /dev/null 2>&1
  git reset --hard "origin/$BRANCH" 2>/dev/null || git reset --hard origin/master 2>/dev/null
  echo -e "   ${GREEN}✅ Código atualizado via git${NC}"
  cd "$SCRIPT_DIR"
else
  echo -e "   ${YELLOW}⚠️  Sem repo configurado — pulando download de código${NC}"
fi

# ── 4. Restaurar .env ──
cp "$ENV_BACKUP" "$SCRIPT_DIR/.env"
cd "$SCRIPT_DIR"
chmod +x *.sh 2>/dev/null || true
chmod +x volumes/db/init/*.sh 2>/dev/null || true

# ── 5. Sync functions + kong ──
echo -e "\n${BLUE}3️⃣  Sincronizando Functions + Kong...${NC}"
bash sync-functions.sh "$INSTALL_DIR/supabase/functions" "volumes/functions" || echo -e "   ${YELLOW}⚠️  sync-functions com alertas${NC}"
bash render-kong-config.sh || echo -e "   ${YELLOW}⚠️  render-kong com alertas${NC}"
echo -e "   ${GREEN}✅ Functions e Kong sincronizados${NC}"

# ── 6. Rebuild + restart ──
echo -e "\n${BLUE}4️⃣  Rebuild e restart...${NC}"
docker compose build --no-cache frontend >> /dev/null 2>&1 || echo -e "   ${YELLOW}⚠️  Build frontend com alertas${NC}"
docker compose up -d frontend >> /dev/null 2>&1
docker compose up -d --force-recreate functions kong >> /dev/null 2>&1
echo -e "   ${GREEN}✅ Frontend + Functions + Kong reiniciados${NC}"

# ── 7. Bootstrap DB (reaplicar schema/policies) ──
echo -e "\n${BLUE}5️⃣  Reaplicando bootstrap DB + Storage...${NC}"
bash bootstrap-db.sh 2>/dev/null && echo -e "   ${GREEN}✅ Bootstrap concluído${NC}" || echo -e "   ${YELLOW}⚠️  Bootstrap com alertas${NC}"

# ── 8. Validação ──
echo -e "\n${BLUE}6️⃣  Validando...${NC}"
sleep 10

if bash validate-install.sh 2>/dev/null; then
  echo -e "   ${GREEN}✅ Validação OK${NC}"
else
  echo -e "   ${YELLOW}⚠️  Validação com alertas — reiniciando serviços...${NC}"
  docker compose restart auth rest storage kong functions 2>/dev/null || true
  sleep 15
  bash validate-install.sh 2>/dev/null || echo -e "   ${YELLOW}⚠️  Validação ainda com alertas. Debug: docker compose logs --tail=50${NC}"
fi

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}  ✅ Atualização concluída!                            ${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════╝${NC}"
