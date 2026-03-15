#!/bin/bash
# ============================================================
# Renderiza docker/volumes/kong/kong.yml com chaves reais do .env
# Uso: bash render-kong-config.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TEMPLATE_FILE="volumes/kong/kong.yml.template"
OUTPUT_FILE="volumes/kong/kong.yml"

if [ ! -f .env ]; then
  echo "❌ Arquivo .env não encontrado em $SCRIPT_DIR"
  exit 1
fi

if [ ! -f "$TEMPLATE_FILE" ]; then
  echo "❌ Template não encontrado: $TEMPLATE_FILE"
  exit 1
fi

read_env_var() {
  grep -E "^${1}=" .env 2>/dev/null | head -1 | sed "s/^${1}=//" | tr -d '"' | tr -d "'"
}

escape_sed() {
  printf '%s' "$1" | sed 's/[\/&]/\\&/g'
}

ANON_KEY=$(read_env_var "ANON_KEY")
SERVICE_ROLE_KEY=$(read_env_var "SERVICE_ROLE_KEY")

if [ -z "$ANON_KEY" ] || [ "$ANON_KEY" = "CHANGE_ME" ]; then
  echo "❌ ANON_KEY inválida no .env"
  exit 1
fi

if [ -z "$SERVICE_ROLE_KEY" ] || [ "$SERVICE_ROLE_KEY" = "CHANGE_ME" ]; then
  echo "❌ SERVICE_ROLE_KEY inválida no .env"
  exit 1
fi

ANON_ESCAPED=$(escape_sed "$ANON_KEY")
SERVICE_ESCAPED=$(escape_sed "$SERVICE_ROLE_KEY")

sed -e "s|__ANON_KEY__|${ANON_ESCAPED}|g" \
    -e "s|__SERVICE_ROLE_KEY__|${SERVICE_ESCAPED}|g" \
    "$TEMPLATE_FILE" > "$OUTPUT_FILE"

echo "✅ Kong config renderizado com chaves atuais (.env)."
