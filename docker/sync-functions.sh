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

REQUIRED_FUNCTIONS=("chat" "notify-telegram" "create-admin-user" "admin-crud" "ai-insights")

mkdir -p "$TARGET_DIR/main"

for fn in "${REQUIRED_FUNCTIONS[@]}"; do
  src_dir="$SOURCE_DIR/$fn"
  src_index="$src_dir/index.ts"
  dst_dir="$TARGET_DIR/$fn"

  if [ ! -f "$src_index" ]; then
    echo "❌ Função obrigatória ausente no repositório: $src_index"
    exit 1
  fi

  if ! grep -qE '^\s*export\s+default\s' "$src_index"; then
    echo "❌ Função $fn sem export default (obrigatório para runtime self-hosted): $src_index"
    exit 1
  fi

  rm -rf "$dst_dir"
  mkdir -p "$dst_dir"
  cp -R "$src_dir/." "$dst_dir/"
  echo "✅ Função sincronizada: $fn"
done

bash "$SCRIPT_DIR/render-functions-main.sh" "$TARGET_DIR"

# Verificação simples de estrutura (sem boot test que pode travar)
echo "🔎 Validando estrutura de functions..."
VALID=true
for fn in "${REQUIRED_FUNCTIONS[@]}"; do
  if [ ! -f "$TARGET_DIR/$fn/index.ts" ]; then
    echo "❌ Ausente: $TARGET_DIR/$fn/index.ts"
    VALID=false
  fi
done
if [ ! -f "$TARGET_DIR/main/index.ts" ]; then
  echo "❌ Ausente: $TARGET_DIR/main/index.ts"
  VALID=false
fi
if [ "$VALID" = "true" ]; then
  echo "✅ Estrutura de functions validada"
else
  echo "❌ Estrutura incompleta — verifique os erros acima"
  exit 1
fi

echo "✅ Edge Functions sincronizadas em: $TARGET_DIR"
