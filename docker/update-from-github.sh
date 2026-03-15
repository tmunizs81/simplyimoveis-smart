#!/bin/bash
# ============================================================
# Simply Imóveis - Atualizar VPS a partir do GitHub
# Uso: sudo bash update-from-github.sh [repo-url]
# Versão: 2026-03-15-v11-simplified
# ============================================================
set -euo pipefail

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'
INSTALL_DIR="/opt/simply-imoveis"

echo -e "${BLUE}🔄 Atualizando Simply Imóveis...${NC}"

command -v git &>/dev/null || { apt-get update -qq >/dev/null 2>&1; apt-get install -y -qq git >/dev/null 2>&1; }

if [ -d "$INSTALL_DIR/.git" ]; then
  cd "$INSTALL_DIR"
  [ -f docker/.env ] && cp docker/.env /tmp/simply-env-backup
  git fetch --all
  git reset --hard "origin/$(git rev-parse --abbrev-ref HEAD)"
  [ -f /tmp/simply-env-backup ] && cp /tmp/simply-env-backup docker/.env
  echo -e "   ${GREEN}✅ Código atualizado${NC}"
else
  REPO_URL="${1:-}"
  [ -z "$REPO_URL" ] && read -p "URL do repositório: " REPO_URL
  [ -z "$REPO_URL" ] && echo "❌ URL não informada" && exit 1
  [ -f "$INSTALL_DIR/docker/.env" ] && cp "$INSTALL_DIR/docker/.env" /tmp/simply-env-backup
  rm -rf "$INSTALL_DIR"
  git clone "$REPO_URL" "$INSTALL_DIR"
  [ -f /tmp/simply-env-backup ] && cp /tmp/simply-env-backup "$INSTALL_DIR/docker/.env"
  echo -e "   ${GREEN}✅ Repositório clonado${NC}"
fi

cd "$INSTALL_DIR/docker"
chmod +x *.sh 2>/dev/null || true
chmod +x volumes/db/init/*.sh 2>/dev/null || true

# Rebuild
echo -e "${BLUE}🔄 Atualizando serviços...${NC}"
bash sync-functions.sh "$INSTALL_DIR/supabase/functions" "volumes/functions"
bash render-kong-config.sh
docker compose build frontend
docker compose up -d frontend
docker compose up -d --force-recreate functions
echo -e "   ${GREEN}✅ Frontend + Functions atualizados${NC}"

bash sync-db-passwords.sh || echo -e "${YELLOW}⚠️  sync-db-passwords falhou${NC}"
bash ensure-storage-buckets.sh || echo -e "${YELLOW}⚠️  ensure-storage-buckets falhou${NC}"

echo -e "\n${GREEN}✅ Atualização concluída!${NC}"
echo -e "${YELLOW}💡 Validar: bash validate-install.sh${NC}"
