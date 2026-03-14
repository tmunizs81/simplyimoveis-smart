#!/bin/bash
# ============================================================
# Gera ANON_KEY e SERVICE_ROLE_KEY para Supabase
# Uso: bash generate-keys.sh
# ============================================================

set -e

if [ ! -f .env ]; then
  echo "❌ Arquivo .env não encontrado. Execute primeiro: cp .env.example .env"
  exit 1
fi

source .env

if [ -z "$JWT_SECRET" ] || [ "$JWT_SECRET" = "super-secret-jwt-token-with-at-least-32-characters-long" ]; then
  echo "❌ Configure JWT_SECRET no .env primeiro."
  exit 1
fi

echo "🔑 Gerando chaves JWT..."

# Precisa do Node.js para gerar os tokens
if ! command -v node &> /dev/null; then
  echo "⚠️  Node.js não encontrado. Instalando via Docker..."
  
  ANON=$(docker run --rm node:20-alpine node -e "
    const crypto = require('crypto');
    const header = Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url');
    const payload = Buffer.from(JSON.stringify({ref:'simply',role:'anon',iss:'supabase',iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+315360000})).toString('base64url');
    const sig = crypto.createHmac('sha256','${JWT_SECRET}').update(header+'.'+payload).digest('base64url');
    console.log(header+'.'+payload+'.'+sig);
  ")

  SERVICE=$(docker run --rm node:20-alpine node -e "
    const crypto = require('crypto');
    const header = Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url');
    const payload = Buffer.from(JSON.stringify({ref:'simply',role:'service_role',iss:'supabase',iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+315360000})).toString('base64url');
    const sig = crypto.createHmac('sha256','${JWT_SECRET}').update(header+'.'+payload).digest('base64url');
    console.log(header+'.'+payload+'.'+sig);
  ")
else
  ANON=$(node -e "
    const crypto = require('crypto');
    const header = Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url');
    const payload = Buffer.from(JSON.stringify({ref:'simply',role:'anon',iss:'supabase',iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+315360000})).toString('base64url');
    const sig = crypto.createHmac('sha256','${JWT_SECRET}').update(header+'.'+payload).digest('base64url');
    console.log(header+'.'+payload+'.'+sig);
  ")

  SERVICE=$(node -e "
    const crypto = require('crypto');
    const header = Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url');
    const payload = Buffer.from(JSON.stringify({ref:'simply',role:'service_role',iss:'supabase',iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+315360000})).toString('base64url');
    const sig = crypto.createHmac('sha256','${JWT_SECRET}').update(header+'.'+payload).digest('base64url');
    console.log(header+'.'+payload+'.'+sig);
  ")
fi

# Atualiza o .env
sed -i "s|^ANON_KEY=.*|ANON_KEY=${ANON}|" .env
sed -i "s|^SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=${SERVICE}|" .env

echo "✅ Chaves geradas e salvas no .env!"
echo ""
echo "ANON_KEY=${ANON}"
echo ""
echo "SERVICE_ROLE_KEY=${SERVICE}"
