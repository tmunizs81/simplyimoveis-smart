#!/bin/bash
# Wrapper: validate.sh → validate-install.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/validate-install.sh" "$@"
