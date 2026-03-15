#!/bin/bash
# ============================================================
# Gera ANON_KEY e SERVICE_ROLE_KEY
# Uso: bash generate-keys.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f .env ]; then
  echo "❌ Arquivo .env não encontrado. Execute primeiro: cp .env.example .env"
  exit 1
fi

read_env_var() {
  grep -E "^${1}=" .env 2>/dev/null | head -1 | sed "s/^${1}=//" | tr -d '"' | tr -d "'"
}

JWT_SECRET=$(read_env_var "JWT_SECRET")

if [ -z "$JWT_SECRET" ] || [ "$JWT_SECRET" = "super-secret-jwt-token-with-at-least-32-characters-long" ]; then
  echo "❌ Configure JWT_SECRET no .env primeiro."
  exit 1
fi

echo "🔑 Gerando chaves JWT..."

generate_jwt() {
  local role="$1"
  local js_code="
    const crypto = require('crypto');
    const header = Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url');
    const payload = Buffer.from(JSON.stringify({ref:'simply',role:'${role}',iss:'supabase',iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+315360000})).toString('base64url');
    const sig = crypto.createHmac('sha256','${JWT_SECRET}').update(header+'.'+payload).digest('base64url');
    console.log(header+'.'+payload+'.'+sig);
  "

  if command -v node &> /dev/null; then
    node -e "$js_code"
  else
    docker run --rm node:20-alpine node -e "$js_code"
  fi
}

ANON=$(generate_jwt "anon")
SERVICE=$(generate_jwt "service_role")

if [ -z "$ANON" ] || [ -z "$SERVICE" ]; then
  echo "❌ Falha ao gerar chaves JWT."
  exit 1
fi

sed -i "s|^ANON_KEY=.*|ANON_KEY=\"${ANON}\"|" .env
sed -i "s|^SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=\"${SERVICE}\"|" .env

if [ -f render-kong-config.sh ]; then
  bash render-kong-config.sh >/dev/null
fi

echo "✅ Chaves geradas e salvas no .env!"
echo ""
echo "ANON_KEY=${ANON}"
echo ""
echo "SERVICE_ROLE_KEY=${SERVICE}"
