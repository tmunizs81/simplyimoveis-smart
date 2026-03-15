#!/bin/bash
# ============================================================
# Reparo do banco para resolver loops auth/storage sem reinstalar
# Uso: bash repair-runtime-db.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🛠️ Aplicando reparo de permissões e search_path..."
bash sync-db-passwords.sh

echo "🔄 Reiniciando serviços dependentes..."
docker compose restart auth rest storage kong
sleep 20

echo "🧪 Validando stack..."
bash validate-install.sh

echo "✅ Reparo concluído"