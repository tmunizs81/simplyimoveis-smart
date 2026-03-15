#!/bin/bash
# ============================================================
# Sincroniza Edge Functions locais para runtime self-hosted
# Uso: bash sync-functions.sh [source_dir] [target_dir]
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SOURCE_DIR="${1:-$SCRIPT_DIR/../supabase/functions}"
TARGET_DIR="${2:-$SCRIPT_DIR/volumes/functions}"

REQUIRED_FUNCTIONS=("chat" "notify-telegram" "create-admin-user")

mkdir -p "$TARGET_DIR/main"

for fn in "${REQUIRED_FUNCTIONS[@]}"; do
  src="$SOURCE_DIR/$fn/index.ts"
  dst_dir="$TARGET_DIR/$fn"
  dst="$dst_dir/index.ts"

  if [ ! -f "$src" ]; then
    echo "❌ Função obrigatória ausente no repositório: $src"
    exit 1
  fi

  mkdir -p "$dst_dir"
  cp "$src" "$dst"
  echo "✅ Função sincronizada: $fn"
done

bash "$SCRIPT_DIR/render-functions-main.sh" "$TARGET_DIR"

echo "✅ Edge Functions sincronizadas em: $TARGET_DIR"