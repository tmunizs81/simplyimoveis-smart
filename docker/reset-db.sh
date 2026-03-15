#!/bin/bash
# ============================================================
# Simply Imóveis - Reset APENAS do banco de dados
# Uso: sudo bash reset-db.sh [--no-backup]
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

[ ! -f .env ] && echo -e "${RED}❌ .env não encontrado em $SCRIPT_DIR${NC}" && exit 1
[ ! -f bootstrap-db.sh ] && echo -e "${RED}❌ bootstrap-db.sh não encontrado${NC}" && exit 1

read_env() { grep -E "^${1}=" "$SCRIPT_DIR/.env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"; }

POSTGRES_DB=$(read_env "POSTGRES_DB"); POSTGRES_DB="${POSTGRES_DB:-simply_db}"
BACKUP_DIR="/opt/simply-imoveis/backups"

echo -e "${RED}⚠️  Reset do banco de dados: $POSTGRES_DB${NC}"
echo -e "${RED}   Todos os dados serão DESTRUÍDOS!${NC}"

if [[ "${1:-}" != "--no-backup" ]]; then
  echo -e "${BLUE}💾 Fazendo backup...${NC}"
  mkdir -p "$BACKUP_DIR"
  DATE=$(date +%Y-%m-%d_%H%M)
  docker exec simply-db pg_dump -U supabase_admin "$POSTGRES_DB" 2>/dev/null | gzip > "$BACKUP_DIR/pre-reset-${DATE}.sql.gz" && \
    echo -e "   ${GREEN}✅ Backup: $BACKUP_DIR/pre-reset-${DATE}.sql.gz${NC}" || \
    echo -e "   ${YELLOW}⚠️  Backup falhou${NC}"
fi

read -p "Digite RESETAR para confirmar: " CONFIRM
[ "$CONFIRM" != "RESETAR" ] && echo "Cancelado." && exit 0

echo -e "${BLUE}🔄 Parando serviços...${NC}"
docker compose stop auth rest storage functions frontend 2>/dev/null || true
docker compose stop db 2>/dev/null || true
docker compose rm -f db 2>/dev/null || true

for v in $(docker volume ls --filter "name=simply_pgdata" -q 2>/dev/null); do docker volume rm -f "$v" 2>/dev/null || true; done
for v in $(docker volume ls --filter "name=docker_simply_pgdata" -q 2>/dev/null); do docker volume rm -f "$v" 2>/dev/null || true; done

echo -e "${BLUE}🐘 Recriando banco...${NC}"
docker compose up -d db

echo -e "${BLUE}⏳ Aguardando banco...${NC}"
for i in {1..60}; do
  docker exec simply-db pg_isready -U supabase_admin -d "$POSTGRES_DB" -q 2>/dev/null && break
  [ "$i" = "60" ] && echo -e "${RED}❌ Banco não respondeu${NC}" && exit 1
  sleep 2
done
sleep 15

echo -e "${BLUE}🧱 Bootstrap...${NC}"
bash bootstrap-db.sh || { echo -e "${RED}❌ Bootstrap falhou${NC}"; exit 1; }

echo -e "${BLUE}🚀 Subindo serviços...${NC}"
docker compose up -d
sleep 15

echo -e "${BLUE}🧪 Validando...${NC}"
bash validate-install.sh || echo -e "${YELLOW}⚠️  Validação com alertas${NC}"

echo -e "${GREEN}✅ Banco resetado!${NC}"
echo -e "${YELLOW}⚠️  Crie o admin: bash create-admin.sh email senha${NC}"
