#!/bin/bash
set -euo pipefail

# ============================================================
#  Simply Imóveis - Atualizador
#  Uso: sudo bash update.sh
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="/opt/simply-imoveis"

echo -e "${BLUE}🔄 Atualizando Simply Imóveis...${NC}"

cd "$INSTALL_DIR"

# Backup antes de atualizar
echo -e "${BLUE}💾 Fazendo backup antes da atualização...${NC}"
cd docker && bash backup.sh && cd ..

# Pull das mudanças
echo -e "${BLUE}📥 Baixando atualizações do GitHub...${NC}"
git fetch origin
git reset --hard origin/main 2>/dev/null || git reset --hard origin/master

# Atualizar edge functions
echo -e "${BLUE}📦 Atualizando Edge Functions...${NC}"
cp supabase/functions/chat/index.ts docker/volumes/functions/chat/index.ts
cp supabase/functions/create-admin-user/index.ts docker/volumes/functions/create-admin-user/index.ts

# Rebuild e restart
cd docker
echo -e "${BLUE}🔨 Reconstruindo frontend...${NC}"
docker compose build --no-cache frontend

echo -e "${BLUE}🔄 Reiniciando serviços...${NC}"
docker compose up -d

echo ""
echo -e "${GREEN}✅ Atualização concluída!${NC}"
echo -e "${GREEN}   Verifique: docker compose ps${NC}"
