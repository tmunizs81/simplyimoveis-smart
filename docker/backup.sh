#!/bin/bash
# ============================================================
# Simply Imóveis - Backup automático
# Uso: bash backup.sh
# Agendar via cron: 0 2 * * * /opt/simply-imoveis/docker/backup.sh
# ============================================================

set -e

source "$(dirname "$0")/.env"

BACKUP_DIR="/opt/simply-imoveis/backups"
DATE=$(date +%Y-%m-%d_%H%M)
BACKUP_FILE="${BACKUP_DIR}/simply-backup-${DATE}.sql.gz"

mkdir -p "$BACKUP_DIR"

echo "🔄 Iniciando backup do banco de dados..."

docker exec simply-db pg_dump -U supabase_admin ${POSTGRES_DB:-simply_db} | gzip > "$BACKUP_FILE"

# Backup dos arquivos de storage
STORAGE_BACKUP="${BACKUP_DIR}/simply-storage-${DATE}.tar.gz"
docker run --rm -v simply-imoveis_simply_storage:/data -v "${BACKUP_DIR}":/backup alpine \
  tar czf "/backup/simply-storage-${DATE}.tar.gz" -C /data .

echo "✅ Backup concluído!"
echo "   DB: ${BACKUP_FILE}"
echo "   Storage: ${STORAGE_BACKUP}"

# Remove backups com mais de 30 dias
find "$BACKUP_DIR" -name "simply-backup-*.sql.gz" -mtime +30 -delete
find "$BACKUP_DIR" -name "simply-storage-*.tar.gz" -mtime +30 -delete

echo "🗑️  Backups antigos (>30 dias) removidos."
