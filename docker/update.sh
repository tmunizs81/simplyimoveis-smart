#!/bin/bash
# ============================================================
# Simply Imóveis - Atualizar (backup + pull + rebuild)
# Uso: sudo bash update.sh
# ============================================================
set -euo pipefail

INSTALL_DIR="/opt/simply-imoveis"
cd "$INSTALL_DIR"

echo "💾 Fazendo backup..."
cd docker && bash backup.sh && cd ..

echo "📥 Baixando atualizações..."
git fetch origin
git reset --hard origin/main 2>/dev/null || git reset --hard origin/master

cd docker
chmod +x *.sh 2>/dev/null || true
chmod +x volumes/db/init/*.sh 2>/dev/null || true

bash sync-functions.sh "$INSTALL_DIR/supabase/functions" "volumes/functions"
bash render-kong-config.sh
docker compose build --no-cache frontend
docker compose up -d frontend
docker compose up -d --force-recreate functions
bash sync-db-passwords.sh || echo "⚠️  sync-db-passwords falhou"
bash ensure-storage-buckets.sh || echo "⚠️  ensure-storage-buckets falhou"

echo "✅ Atualização concluída!"
