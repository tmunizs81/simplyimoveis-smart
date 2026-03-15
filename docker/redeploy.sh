#!/bin/bash
# ============================================================
# Simply Imóveis - Redeploy (rebuild + restart sem perder dados)
# Uso: sudo bash redeploy.sh [--full]
# --full: rebuild TODAS as imagens (não apenas frontend)
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

# Sync functions
echo -e "${BLUE}📦 Sincronizando functions...${NC}"
bash sync-functions.sh "$INSTALL_DIR/supabase/functions" "volumes/functions"

# Render Kong config
echo -e "${BLUE}🔧 Renderizando Kong config...${NC}"
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

echo -e "${BLUE}⏳ Aguardando serviços (15s)...${NC}"
sleep 15

# Sync passwords (garante roles e grants)
echo -e "${BLUE}🔐 Sincronizando credenciais...${NC}"
bash sync-db-passwords.sh || echo -e "${YELLOW}⚠️  sync-db-passwords falhou${NC}"

# Buckets
bash ensure-storage-buckets.sh || echo -e "${YELLOW}⚠️  ensure-storage-buckets falhou${NC}"

# Validate
echo -e "${BLUE}🧪 Validando...${NC}"
bash validate-install.sh || echo -e "${YELLOW}⚠️  Validação com alertas${NC}"

echo -e "${GREEN}✅ Redeploy concluído!${NC}"
