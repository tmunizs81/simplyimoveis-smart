#!/bin/bash
# ============================================================
# Simply Imóveis - Restaurar backup
# Uso: bash restore.sh /caminho/do/backup.sql.gz
# ============================================================

set -e

BACKUP_FILE=${1}

if [ -z "$BACKUP_FILE" ]; then
  echo "Uso: bash restore.sh /caminho/do/backup.sql.gz"
  echo ""
  echo "Backups disponíveis:"
  ls -la /opt/simply-imoveis/backups/simply-backup-*.sql.gz 2>/dev/null || echo "  Nenhum backup encontrado."
  exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
  echo "❌ Arquivo não encontrado: $BACKUP_FILE"
  exit 1
fi

source "$(dirname "$0")/.env"

echo "⚠️  ATENÇÃO: Isso substituirá TODOS os dados atuais!"
read -p "Tem certeza? (digite SIM para confirmar): " CONFIRM

if [ "$CONFIRM" != "SIM" ]; then
  echo "❌ Restauração cancelada."
  exit 0
fi

echo "🔄 Restaurando banco de dados..."

# Para os serviços que usam o banco
docker compose -f "$(dirname "$0")/docker-compose.yml" stop auth rest storage functions

# Restaura o dump
gunzip -c "$BACKUP_FILE" | docker exec -i simply-db psql -U supabase_admin -d ${POSTGRES_DB:-simply_db}

# Reinicia tudo
docker compose -f "$(dirname "$0")/docker-compose.yml" up -d

echo "✅ Banco restaurado com sucesso!"

# Se tiver backup de storage correspondente
STORAGE_FILE=$(echo "$BACKUP_FILE" | sed 's/simply-backup/simply-storage/' | sed 's/.sql.gz/.tar.gz/')
if [ -f "$STORAGE_FILE" ]; then
  echo "🔄 Restaurando arquivos de storage..."
  docker run --rm -v simply-imoveis_simply_storage:/data -v "$(dirname "$STORAGE_FILE")":/backup alpine \
    sh -c "rm -rf /data/* && tar xzf /backup/$(basename "$STORAGE_FILE") -C /data"
  echo "✅ Storage restaurado!"
fi

echo ""
echo "🎉 Restauração completa!"
