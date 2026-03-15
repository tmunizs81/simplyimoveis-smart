#!/bin/bash
# ============================================================
# Simply Imóveis - Atualizar (backup + pull + rebuild)
# Uso: sudo bash update.sh
# ============================================================
set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/simply-imoveis"

cd "$INSTALL_DIR"

echo -e "${BLUE}💾 Fazendo backup antes de atualizar...${NC}"
cd docker && bash backup.sh && cd ..

echo -e "${BLUE}📥 Baixando atualizações...${NC}"
git fetch origin
git reset --hard origin/main 2>/dev/null || git reset --hard origin/master

cd docker
chmod +x *.sh 2>/dev/null || true
chmod +x volumes/db/init/*.sh 2>/dev/null || true

echo -e "${BLUE}📦 Sincronizando functions...${NC}"
bash sync-functions.sh "$INSTALL_DIR/supabase/functions" "volumes/functions"
bash render-kong-config.sh

echo -e "${BLUE}🏗️  Rebuild e deploy...${NC}"
docker compose build --no-cache frontend
docker compose up -d frontend
docker compose up -d --force-recreate functions kong

echo -e "${BLUE}🧱 Reaplicando pipeline de bootstrap (DB + Storage)...${NC}"
if ! bash bootstrap-db.sh; then
  echo -e "${YELLOW}⚠️  bootstrap-db falhou. Debug: docker compose logs --tail=120 db rest storage${NC}"
fi

echo -e "${BLUE}🧪 Validando...${NC}"
if ! bash validate-install.sh; then
  echo -e "${YELLOW}⚠️  Validação falhou. Reiniciando...${NC}"
  docker compose restart auth rest storage kong functions
  sleep 15
  bash validate-install.sh || echo -e "${YELLOW}⚠️  Validação ainda com problemas${NC}"
fi

echo -e "${GREEN}✅ Atualização concluída!${NC}"
