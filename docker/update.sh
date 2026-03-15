#!/bin/bash
# ============================================================
# Simply Imóveis - Atualizar (backup + pull + rebuild)
# Uso: sudo bash update.sh
# ============================================================
set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

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
docker compose up -d --force-recreate functions

echo -e "${BLUE}🔐 Sincronizando credenciais...${NC}"
bash sync-db-passwords.sh || echo -e "${YELLOW}⚠️  sync-db-passwords falhou${NC}"
bash ensure-storage-buckets.sh || echo -e "${YELLOW}⚠️  ensure-storage-buckets falhou${NC}"

echo -e "${BLUE}🧪 Validando...${NC}"
if ! bash validate-install.sh; then
  echo -e "${YELLOW}⚠️  Validação falhou. Rodando reparo...${NC}"
  POSTGRES_PASSWORD=$(grep -E "^POSTGRES_PASSWORD=" .env | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
  docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" simply-db \
    psql -v ON_ERROR_STOP=1 -w -h 127.0.0.1 -U supabase_admin -d simply_db < sql/selfhosted-admin-recovery.sql 2>/dev/null || true
  docker compose restart auth rest functions
  sleep 15
  bash validate-install.sh || echo -e "${YELLOW}⚠️  Validação ainda com problemas${NC}"
fi

echo -e "${GREEN}✅ Atualização concluída!${NC}"
