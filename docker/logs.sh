#!/bin/bash
# ============================================================
# Simply Imóveis - Visualizar logs
# Uso: bash logs.sh [servico] [--lines N]
# Exemplos:
#   bash logs.sh              # todos os serviços
#   bash logs.sh functions    # apenas functions
#   bash logs.sh db --lines 100
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SERVICE="${1:-}"
LINES=50

# Parse --lines
for i in "$@"; do
  if [[ "$i" == "--lines" ]]; then
    shift
    LINES="${1:-50}"
  fi
done

if [ -z "$SERVICE" ]; then
  docker compose logs --tail="$LINES" -f
else
  docker compose logs --tail="$LINES" -f "$SERVICE"
fi
