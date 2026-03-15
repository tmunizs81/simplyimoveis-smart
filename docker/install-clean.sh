#!/bin/bash
# ============================================================
# Simply Imóveis - Instalação LIMPA (zera banco e volumes)
# Uso: sudo bash install-clean.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🧹 Instalação limpa: containers e volumes serão removidos."
exec bash install.sh --clean
