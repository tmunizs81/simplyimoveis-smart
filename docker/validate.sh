#!/bin/bash
# Wrapper compatível com o nome solicitado: validate.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/validate-install.sh"
