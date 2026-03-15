#!/bin/bash
# ============================================================
# Simply Imóveis - Reset controlado do banco
# Uso: sudo bash reset-db.sh [--no-backup]
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
BOOTSTRAP_SCRIPT="$SCRIPT_DIR/bootstrap-db.sh"
VALIDATE_SCRIPT="$SCRIPT_DIR/validate-install.sh"
BACKUP_DIR="/opt/simply-imoveis/backups"

[ -f "$ENV_FILE" ] || { echo -e "${RED}❌ .env não encontrado: $ENV_FILE${NC}"; exit 1; }
[ -f "$COMPOSE_FILE" ] || { echo -e "${RED}❌ docker-compose.yml ausente: $COMPOSE_FILE${NC}"; exit 1; }
[ -f "$BOOTSTRAP_SCRIPT" ] || { echo -e "${RED}❌ bootstrap-db.sh ausente: $BOOTSTRAP_SCRIPT${NC}"; exit 1; }

read_env() {
  local key="$1"
  grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"
}

compose() {
  docker compose -f "$COMPOSE_FILE" --project-directory "$SCRIPT_DIR" "$@"
}

POSTGRES_DB="$(read_env "POSTGRES_DB")"; POSTGRES_DB="${POSTGRES_DB:-simply_db}"
DB_USER="$(read_env "POSTGRES_USER")"; DB_USER="${DB_USER:-supabase_admin}"

NO_BACKUP=false
[[ "${1:-}" == "--no-backup" ]] && NO_BACKUP=true

echo -e "${RED}⚠️  Reset do banco ${POSTGRES_DB}${NC}"
echo -e "${RED}   Todos os dados de banco serão destruídos.${NC}"

if [ "$NO_BACKUP" = "false" ]; then
  echo -e "${BLUE}💾 Gerando backup pré-reset...${NC}"
  mkdir -p "$BACKUP_DIR"
  DATE=$(date +%Y-%m-%d_%H%M%S)
  if docker exec simply-db pg_dump -U "$DB_USER" "$POSTGRES_DB" 2>/dev/null | gzip > "$BACKUP_DIR/pre-reset-${DATE}.sql.gz"; then
    echo -e "   ${GREEN}✅ Backup: $BACKUP_DIR/pre-reset-${DATE}.sql.gz${NC}"
  else
    echo -e "   ${YELLOW}⚠️  Não foi possível gerar backup (seguindo mesmo assim).${NC}"
  fi
fi

read -p "Digite RESETAR para confirmar: " CONFIRM
[ "$CONFIRM" = "RESETAR" ] || { echo "Cancelado."; exit 0; }

echo -e "${BLUE}🛑 Parando stack...${NC}"
compose down --remove-orphans >/dev/null 2>&1 || true

echo -e "${BLUE}🧹 Removendo volume de banco do projeto...${NC}"
for volume in $(docker volume ls --format '{{.Name}}' | grep -E '(^|_)simply_pgdata$' || true); do
  docker volume rm -f "$volume" >/dev/null 2>&1 || true
done

echo -e "${BLUE}🐘 Subindo DB limpo...${NC}"
compose up -d db >/dev/null

echo -e "${BLUE}⏳ Aguardando PostgreSQL...${NC}"
for i in {1..90}; do
  if compose exec -T db pg_isready -U "$DB_USER" -d "$POSTGRES_DB" -q 2>/dev/null; then
    break
  fi
  [ "$i" = "90" ] && { echo -e "${RED}❌ PostgreSQL não respondeu em 180s${NC}"; exit 1; }
  sleep 2
done

echo -e "${BLUE}🧱 Executando bootstrap completo...${NC}"
bash "$BOOTSTRAP_SCRIPT"

echo -e "${BLUE}🚀 Subindo stack completa...${NC}"
compose up -d --build --remove-orphans >/dev/null
sleep 15

echo -e "${BLUE}🧪 Validando instalação...${NC}"
if [ -f "$VALIDATE_SCRIPT" ]; then
  bash "$VALIDATE_SCRIPT"
fi

echo -e "${GREEN}✅ Reset de banco concluído com sucesso.${NC}"
