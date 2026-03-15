#!/bin/bash
# ============================================================
# Wrapper robusto para validação estrutural
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/validate-install.sh"

[ -f "$TARGET" ] || {
  echo "❌ validate-install.sh não encontrado em: $TARGET"
  exit 1
}

exec bash "$TARGET" "$@"
