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

echo -e "${BLUE}🔐 Sincronizando credenciais...${NC}"
bash sync-db-passwords.sh || echo -e "${YELLOW}⚠️  sync-db-passwords falhou${NC}"

# Recovery SQL via stdin (arquivo no host)
read_env() { grep -E "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"; }
POSTGRES_PASSWORD=$(read_env "POSTGRES_PASSWORD")
POSTGRES_DB=$(read_env "POSTGRES_DB"); POSTGRES_DB="${POSTGRES_DB:-simply_db}"
DB_USER=$(read_env "POSTGRES_USER"); DB_USER="${DB_USER:-supabase_admin}"

if [ -f "$SCRIPT_DIR/sql/selfhosted-admin-recovery.sql" ]; then
  docker compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" db \
    psql -v ON_ERROR_STOP=1 -w -h 127.0.0.1 -U "$DB_USER" -d "$POSTGRES_DB" \
    < "$SCRIPT_DIR/sql/selfhosted-admin-recovery.sql" 2>/dev/null || echo -e "${YELLOW}⚠️  Recovery SQL com alertas${NC}"
fi

bash ensure-storage-buckets.sh || echo -e "${YELLOW}⚠️  ensure-storage-buckets falhou${NC}"

echo -e "${BLUE}🧪 Validando...${NC}"
if ! bash validate-install.sh; then
  echo -e "${YELLOW}⚠️  Validação falhou. Reiniciando...${NC}"
  docker compose restart auth rest storage kong functions
  sleep 15
  bash validate-install.sh || echo -e "${YELLOW}⚠️  Validação ainda com problemas${NC}"
fi

echo -e "${GREEN}✅ Atualização concluída!${NC}"
