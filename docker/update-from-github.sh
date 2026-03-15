#!/bin/bash
# ============================================================
# Simply Imóveis - Atualizar VPS a partir do GitHub
# Uso: sudo bash update-from-github.sh [repo-url]
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

echo -e "${BLUE}🔄 Atualizando serviços...${NC}"
bash sync-functions.sh "$INSTALL_DIR/supabase/functions" "volumes/functions"
bash render-kong-config.sh
docker compose build --no-cache frontend
docker compose up -d frontend
docker compose up -d --force-recreate functions
echo -e "   ${GREEN}✅ Frontend + Functions atualizados${NC}"

bash sync-db-passwords.sh || echo -e "${YELLOW}⚠️  sync-db-passwords falhou${NC}"
bash ensure-storage-buckets.sh || echo -e "${YELLOW}⚠️  ensure-storage-buckets falhou${NC}"

echo -e "${BLUE}🧪 Validando...${NC}"
if ! bash validate-install.sh; then
  echo -e "${YELLOW}⚠️  Validação falhou. Aplicando recovery SQL...${NC}"
  POSTGRES_PASSWORD=$(grep -E "^POSTGRES_PASSWORD=" .env | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
  docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" simply-db \
    psql -v ON_ERROR_STOP=1 -w -h 127.0.0.1 -U supabase_admin -d simply_db < sql/selfhosted-admin-recovery.sql 2>/dev/null || true
  docker compose restart auth rest functions
  sleep 15
  bash validate-install.sh || echo -e "${YELLOW}⚠️  Validação ainda com alertas${NC}"
fi

echo -e "\n${GREEN}✅ Atualização concluída!${NC}"
