#!/bin/bash
# ============================================================
# Simply Imóveis - Atualizar VPS a partir do GitHub
# Uso: sudo bash update-from-github.sh
# ============================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

INSTALL_DIR="/opt/simply-imoveis"
REPO_URL="${1:-}"

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║   Simply Imóveis - Atualizar a partir do GitHub      ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ── 1. Verificar git ─────────────────────────────────────────
if ! command -v git &>/dev/null; then
  echo -e "${YELLOW}⚠️  Instalando git...${NC}"
  apt-get update -qq >/dev/null 2>&1
  apt-get install -y -qq git >/dev/null 2>&1
fi

# ── 2. Detectar ou clonar repositório ────────────────────────
if [ -d "$INSTALL_DIR/.git" ]; then
  echo -e "${BLUE}📥 Repositório existente detectado. Atualizando...${NC}"
  cd "$INSTALL_DIR"
  
  # Salvar .env do docker antes do pull
  if [ -f docker/.env ]; then
    cp docker/.env /tmp/simply-env-backup
    echo -e "   ${GREEN}✅ Backup do .env salvo${NC}"
  fi

  git fetch --all
  BRANCH=$(git rev-parse --abbrev-ref HEAD)
  echo -e "   Branch: ${BRANCH}"
  git reset --hard "origin/${BRANCH}"
  echo -e "   ${GREEN}✅ Código atualizado${NC}"

  # Restaurar .env
  if [ -f /tmp/simply-env-backup ]; then
    cp /tmp/simply-env-backup docker/.env
    echo -e "   ${GREEN}✅ .env restaurado${NC}"
  fi

else
  # Precisa da URL do repo
  if [ -z "$REPO_URL" ]; then
    echo -e "${CYAN}📝 URL do repositório GitHub (ex: https://github.com/user/repo.git):${NC}"
    read -p "   > " REPO_URL
  fi

  [ -z "$REPO_URL" ] && echo -e "${RED}❌ URL do repositório não informada${NC}" && exit 1

  echo -e "${BLUE}📥 Clonando repositório...${NC}"
  
  # Salvar .env existente se houver
  if [ -f "$INSTALL_DIR/docker/.env" ]; then
    cp "$INSTALL_DIR/docker/.env" /tmp/simply-env-backup
  fi

  rm -rf "$INSTALL_DIR"
  git clone "$REPO_URL" "$INSTALL_DIR"
  echo -e "   ${GREEN}✅ Repositório clonado${NC}"

  # Restaurar .env
  if [ -f /tmp/simply-env-backup ]; then
    cp /tmp/simply-env-backup "$INSTALL_DIR/docker/.env"
    echo -e "   ${GREEN}✅ .env restaurado${NC}"
  fi
fi

# ── 3. Permissões ────────────────────────────────────────────
cd "$INSTALL_DIR/docker"
chmod +x *.sh 2>/dev/null || true
chmod +x volumes/db/init/*.sh 2>/dev/null || true

# ── 4. Rebuild e restart ─────────────────────────────────────
echo ""
echo -e "${BLUE}🔄 Rebuilding e reiniciando serviços...${NC}"

# Copiar edge functions
mkdir -p volumes/functions/{main,chat,notify-telegram,create-admin-user}
cp "$INSTALL_DIR/supabase/functions/chat/index.ts" volumes/functions/chat/index.ts 2>/dev/null || true
cp "$INSTALL_DIR/supabase/functions/notify-telegram/index.ts" volumes/functions/notify-telegram/index.ts 2>/dev/null || true
cp "$INSTALL_DIR/supabase/functions/create-admin-user/index.ts" volumes/functions/create-admin-user/index.ts 2>/dev/null || true

# Renderizar Kong config
bash render-kong-config.sh

# Rebuild frontend (sem tocar no banco)
docker compose build frontend
docker compose up -d frontend
echo -e "   ${GREEN}✅ Frontend atualizado${NC}"

# Restart functions
docker compose up -d --force-recreate functions
echo -e "   ${GREEN}✅ Edge Functions atualizadas${NC}"

echo -e "   ${BLUE}🔐 Reaplicando grants e credenciais internas...${NC}"
bash sync-db-passwords.sh || echo -e "   ${YELLOW}⚠️  Não foi possível reaplicar grants agora${NC}"

echo -e "   ${BLUE}🔐 Reaplicando buckets e políticas de storage...${NC}"
bash ensure-storage-buckets.sh || echo -e "   ${YELLOW}⚠️  Não foi possível reaplicar políticas agora${NC}"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        ✅ Atualização concluída!                     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}💡 Para reinstalar tudo (incluindo banco): sudo bash install.sh${NC}"
echo -e "${YELLOW}💡 Para validar: bash validate-install.sh${NC}"