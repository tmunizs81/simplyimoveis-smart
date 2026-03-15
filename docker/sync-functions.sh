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

REQUIRED_FUNCTIONS=("chat" "notify-telegram" "create-admin-user" "admin-crud")

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

if command -v docker >/dev/null 2>&1; then
  echo "🔎 Validando boot do runtime de functions..."
  # Run with longer timeout and capture logs
  BOOT_LOGS=$(timeout 30s docker run --rm \
    -v "$TARGET_DIR:/home/deno/functions:ro" \
    supabase/edge-runtime:v1.62.2 \
    start --main-service /home/deno/functions/main 2>&1 || true)

  if echo "$BOOT_LOGS" | grep -Eqi "main worker boot error|worker boot error|boot error"; then
    echo "❌ Falha de boot no runtime de functions detectada durante sincronização"
    echo "$BOOT_LOGS" | tail -n 30
    exit 1
  fi

  # "booted" or "Listening on" both indicate successful start
  if echo "$BOOT_LOGS" | grep -Eqi "booted|listening on"; then
    echo "✅ Runtime de functions validado com sucesso"
  else
    echo "ℹ️  Boot check: sem erros detectados (boot pode levar mais tempo em primeira execução)"
  fi
fi

echo "✅ Edge Functions sincronizadas em: $TARGET_DIR"
