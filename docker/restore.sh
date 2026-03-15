#!/bin/bash
# ============================================================
# Simply Imóveis - Restaurar backup
# Uso: bash restore.sh /caminho/do/backup.sql.gz
# ============================================================
set -euo pipefail

BACKUP_FILE="${1:-}"

if [ -z "$BACKUP_FILE" ]; then
  echo "Uso: bash restore.sh /caminho/do/backup.sql.gz"
  echo ""
  echo "Backups disponíveis:"
  ls -la /opt/simply-imoveis/backups/simply-backup-*.sql.gz 2>/dev/null || echo "  Nenhum backup encontrado."
  exit 1
fi

[ ! -f "$BACKUP_FILE" ] && echo "❌ Arquivo não encontrado: $BACKUP_FILE" && exit 1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

[ ! -f .env ] && echo "❌ .env não encontrado" && exit 1

read_env() { grep -E "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"; }

POSTGRES_DB=$(read_env "POSTGRES_DB"); POSTGRES_DB="${POSTGRES_DB:-simply_db}"
POSTGRES_PASSWORD=$(read_env "POSTGRES_PASSWORD")

echo "⚠️  ATENÇÃO: Isso substituirá TODOS os dados atuais!"
read -p "Tem certeza? (digite SIM para confirmar): " CONFIRM
[ "$CONFIRM" != "SIM" ] && echo "❌ Cancelado." && exit 0

echo "🔄 Restaurando banco de dados..."

docker compose stop auth rest storage functions frontend

gunzip -c "$BACKUP_FILE" | docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" simply-db \
  psql -U supabase_admin -h 127.0.0.1 -d "$POSTGRES_DB"

docker compose up -d

echo "✅ Banco restaurado com sucesso!"

# Se tiver backup de storage correspondente
STORAGE_FILE=$(echo "$BACKUP_FILE" | sed 's/simply-backup/simply-storage/' | sed 's/.sql.gz/.tar.gz/')
if [ -f "$STORAGE_FILE" ]; then
  echo "🔄 Restaurando arquivos de storage..."
  docker run --rm \
    -v docker_simply_storage:/data \
    -v "$(dirname "$STORAGE_FILE")":/backup \
    alpine sh -c "rm -rf /data/* && tar xzf /backup/$(basename "$STORAGE_FILE") -C /data" 2>/dev/null || \
  docker run --rm \
    -v simply_storage:/data \
    -v "$(dirname "$STORAGE_FILE")":/backup \
    alpine sh -c "rm -rf /data/* && tar xzf /backup/$(basename "$STORAGE_FILE") -C /data" 2>/dev/null || true
  echo "✅ Storage restaurado!"
fi

echo "🎉 Restauração completa!"
