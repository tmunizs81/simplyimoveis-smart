#!/bin/bash
# ============================================================
# Simply Imóveis - Backup completo (DB + Storage)
# Uso: bash backup.sh [--db-only]
# Agendar via cron: 0 2 * * * /opt/simply-imoveis/docker/backup.sh
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

[ ! -f .env ] && echo -e "${RED}❌ .env não encontrado${NC}" && exit 1

read_env() { grep -E "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"; }

POSTGRES_DB=$(read_env "POSTGRES_DB"); POSTGRES_DB="${POSTGRES_DB:-simply_db}"
POSTGRES_PASSWORD=$(read_env "POSTGRES_PASSWORD")
DB_USER=$(read_env "POSTGRES_USER"); DB_USER="${DB_USER:-supabase_admin}"

BACKUP_DIR="/opt/simply-imoveis/backups"
DATE=$(date +%Y-%m-%d_%H%M)
BACKUP_FILE="${BACKUP_DIR}/simply-backup-${DATE}.sql.gz"
DB_ONLY=false

for arg in "$@"; do
  [ "$arg" = "--db-only" ] && DB_ONLY=true
done

mkdir -p "$BACKUP_DIR"

echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Simply Imóveis — Backup Completo                 ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"

# ── 1) Verificar se o DB está rodando ──
if ! docker exec simply-db pg_isready -U "$DB_USER" -d "$POSTGRES_DB" -q 2>/dev/null; then
  echo -e "${RED}❌ PostgreSQL não está respondendo${NC}"
  exit 1
fi

# ── 2) Dump do banco ──
echo -e "${BLUE}🔄 Exportando banco de dados...${NC}"

docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" simply-db \
  pg_dump \
    -U "$DB_USER" \
    -h 127.0.0.1 \
    -d "$POSTGRES_DB" \
    --clean \
    --if-exists \
    --no-owner \
    --no-privileges \
    --exclude-schema=auth \
    --exclude-schema=storage \
    --exclude-schema=supabase_functions \
    --exclude-schema=realtime \
    --exclude-schema=vault \
    --exclude-schema=pgsodium \
    --exclude-schema=graphql \
    --exclude-schema=graphql_public \
    --exclude-schema=extensions \
    --exclude-schema=_realtime \
    --exclude-schema=supabase_migrations \
    --exclude-schema=_analytics \
    --exclude-schema=_supavisor \
  | gzip > "$BACKUP_FILE"

# Validate dump
DUMP_SIZE=$(stat -c%s "$BACKUP_FILE" 2>/dev/null || stat -f%z "$BACKUP_FILE" 2>/dev/null || echo "0")
if [ "$DUMP_SIZE" -lt 100 ]; then
  echo -e "${RED}❌ Dump parece vazio (${DUMP_SIZE} bytes). Verifique o banco.${NC}"
  rm -f "$BACKUP_FILE"
  exit 1
fi
echo -e "   ${GREEN}✅ DB backup: ${BACKUP_FILE} ($(du -h "$BACKUP_FILE" | cut -f1))${NC}"

# ── 3) Backup dos arquivos de storage ──
if [ "$DB_ONLY" = "false" ]; then
  STORAGE_BACKUP="${BACKUP_DIR}/simply-storage-${DATE}.tar.gz"
  echo -e "${BLUE}🔄 Exportando arquivos de storage...${NC}"

  # Detect volume name
  VOLUME_NAME=""
  for candidate in "docker_simply_storage" "simply_storage" "simply-imoveis_simply_storage"; do
    if docker volume inspect "$candidate" >/dev/null 2>&1; then
      VOLUME_NAME="$candidate"
      break
    fi
  done

  if [ -n "$VOLUME_NAME" ]; then
    docker run --rm \
      -v "${VOLUME_NAME}":/data:ro \
      -v "${BACKUP_DIR}":/backup \
      alpine tar czf "/backup/simply-storage-${DATE}.tar.gz" -C /data . 2>/dev/null

    if [ -f "$STORAGE_BACKUP" ]; then
      echo -e "   ${GREEN}✅ Storage backup: ${STORAGE_BACKUP} ($(du -h "$STORAGE_BACKUP" | cut -f1))${NC}"
    else
      echo -e "   ${YELLOW}⚠️  Storage backup pode ter falhado${NC}"
    fi
  else
    echo -e "   ${YELLOW}⚠️  Volume de storage não encontrado (tentou: docker_simply_storage, simply_storage, simply-imoveis_simply_storage)${NC}"
  fi
fi

# ── 4) Verificação de integridade ──
echo -e "${BLUE}🔎 Verificando integridade...${NC}"

# Count tables in dump
TABLE_COUNT=$(gunzip -c "$BACKUP_FILE" | grep -c "^CREATE TABLE" 2>/dev/null || echo "0")
echo -e "   Tabelas no dump: ${TABLE_COUNT}"

if [ "$TABLE_COUNT" -lt 10 ]; then
  echo -e "   ${YELLOW}⚠️  Poucas tabelas no dump (esperado ~16). Verifique o banco.${NC}"
else
  echo -e "   ${GREEN}✅ Integridade OK${NC}"
fi

# ── 5) Rotação de backups antigos ──
OLD_COUNT=$(find "$BACKUP_DIR" -name "simply-backup-*.sql.gz" -mtime +30 2>/dev/null | wc -l)
find "$BACKUP_DIR" -name "simply-backup-*.sql.gz" -mtime +30 -delete 2>/dev/null || true
find "$BACKUP_DIR" -name "simply-storage-*.tar.gz" -mtime +30 -delete 2>/dev/null || true
[ "$OLD_COUNT" -gt 0 ] && echo -e "   🗑️  ${OLD_COUNT} backup(s) antigo(s) removido(s)"

# ── Summary ──
echo -e "\n${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ Backup concluído com sucesso!                     ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  DB: ${BACKUP_FILE}${NC}"
[ "$DB_ONLY" = "false" ] && [ -f "${STORAGE_BACKUP:-}" ] && echo -e "${GREEN}║  Storage: ${STORAGE_BACKUP}${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Para restaurar: ${BLUE}bash restore.sh ${BACKUP_FILE}${NC}"
