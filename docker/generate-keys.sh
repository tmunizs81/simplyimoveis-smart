#!/bin/bash
# ============================================================
# Gera ANON_KEY e SERVICE_ROLE_KEY para Supabase
# Uso: bash generate-keys.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f .env ]; then
  echo "❌ Arquivo .env não encontrado. Execute primeiro: cp .env.example .env"
  exit 1
fi

# Lê JWT_SECRET do .env de forma segura (sem source)
JWT_SECRET=$(grep -E '^JWT_SECRET=' .env | head -1 | sed 's/^JWT_SECRET=//' | tr -d '"' | tr -d "'")

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

# Atualiza o .env
sed -i "s|^ANON_KEY=.*|ANON_KEY=\"${ANON}\"|" .env
sed -i "s|^SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=\"${SERVICE}\"|" .env

echo "✅ Chaves geradas e salvas no .env!"
echo ""
echo "ANON_KEY=${ANON}"
echo ""
echo "SERVICE_ROLE_KEY=${SERVICE}"
