#!/bin/bash
# ============================================================
# Simply Imóveis - Redeploy (rebuild + restart sem perder dados)
# Uso: sudo bash redeploy.sh [--full]
# ============================================================
set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

[ ! -f .env ] && echo "❌ .env não encontrado" && exit 1

FULL=false
[[ "${1:-}" == "--full" ]] && FULL=true

INSTALL_DIR="/opt/simply-imoveis"

echo -e "${BLUE}🔄 Redeploy Simply Imóveis${NC}"

bash sync-functions.sh "$INSTALL_DIR/supabase/functions" "volumes/functions"
bash render-kong-config.sh

if [ "$FULL" = "true" ]; then
  echo -e "${BLUE}🏗️  Rebuild completo...${NC}"
  docker compose build --no-cache
  docker compose up -d --force-recreate --remove-orphans
else
  echo -e "${BLUE}🏗️  Rebuild frontend...${NC}"
  docker compose build --no-cache frontend
  docker compose up -d frontend
  docker compose up -d --force-recreate functions
fi

echo -e "${BLUE}⏳ Aguardando (15s)...${NC}"
sleep 15

bash sync-db-passwords.sh || echo -e "${YELLOW}⚠️  sync-db-passwords falhou${NC}"
bash ensure-storage-buckets.sh || echo -e "${YELLOW}⚠️  ensure-storage-buckets falhou${NC}"

bash validate-install.sh || echo -e "${YELLOW}⚠️  Validação com alertas${NC}"

echo -e "${GREEN}✅ Redeploy concluído!${NC}"
