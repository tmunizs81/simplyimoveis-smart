#!/bin/bash
# ============================================================
# Simply Imóveis - Backup automático
# Uso: bash backup.sh
# Agendar via cron: 0 2 * * * /opt/simply-imoveis/docker/backup.sh
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

[ ! -f .env ] && echo "❌ .env não encontrado" && exit 1

read_env() { grep -E "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"; }

POSTGRES_DB=$(read_env "POSTGRES_DB"); POSTGRES_DB="${POSTGRES_DB:-simply_db}"
POSTGRES_PASSWORD=$(read_env "POSTGRES_PASSWORD")

BACKUP_DIR="/opt/simply-imoveis/backups"
DATE=$(date +%Y-%m-%d_%H%M)
BACKUP_FILE="${BACKUP_DIR}/simply-backup-${DATE}.sql.gz"

mkdir -p "$BACKUP_DIR"

echo "🔄 Iniciando backup do banco de dados..."

docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" simply-db \
  pg_dump -U supabase_admin -h 127.0.0.1 "$POSTGRES_DB" | gzip > "$BACKUP_FILE"

# Backup dos arquivos de storage
STORAGE_BACKUP="${BACKUP_DIR}/simply-storage-${DATE}.tar.gz"
docker run --rm \
  -v docker_simply_storage:/data \
  -v "${BACKUP_DIR}":/backup \
  alpine tar czf "/backup/simply-storage-${DATE}.tar.gz" -C /data . 2>/dev/null || \
docker run --rm \
  -v simply_storage:/data \
  -v "${BACKUP_DIR}":/backup \
  alpine tar czf "/backup/simply-storage-${DATE}.tar.gz" -C /data . 2>/dev/null || \
echo "⚠️  Storage backup falhou (volume pode ter nome diferente)"

echo "✅ Backup concluído!"
echo "   DB: ${BACKUP_FILE}"
[ -f "$STORAGE_BACKUP" ] && echo "   Storage: ${STORAGE_BACKUP}"

# Remove backups com mais de 30 dias
find "$BACKUP_DIR" -name "simply-backup-*.sql.gz" -mtime +30 -delete 2>/dev/null || true
find "$BACKUP_DIR" -name "simply-storage-*.tar.gz" -mtime +30 -delete 2>/dev/null || true

echo "🗑️  Backups antigos (>30 dias) removidos."
