#!/bin/bash
# ============================================================
# Regenera ANON_KEY e SERVICE_ROLE_KEY a partir do JWT_SECRET
# e recria o admin. Uso: bash fix-auth-keys.sh [email] [senha]
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

[ ! -f .env ] && echo "❌ .env não encontrado em $SCRIPT_DIR" && exit 1

read_env() { grep -E "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"; }

JWT=$(read_env "JWT_SECRET")
[ -z "$JWT" ] && echo "❌ JWT_SECRET vazio no .env" && exit 1

ADMIN_EMAIL="${1:-$(read_env "ADMIN_EMAIL")}"
ADMIN_PASSWORD="${2:-$(read_env "ADMIN_PASSWORD")}"
[ -z "$ADMIN_EMAIL" ] && read -rp "E-mail do admin: " ADMIN_EMAIL
[ -z "$ADMIN_PASSWORD" ] && read -rsp "Senha do admin: " ADMIN_PASSWORD && echo

echo "🔑 JWT_SECRET encontrado. Regenerando chaves..."

# Backup
cp .env ".env.bak.$(date +%F-%H%M%S)"

# Função para gerar JWT
generate_jwt() {
  local ROLE="$1"
  local HEADER PAYLOAD SIGN
  HEADER=$(printf '{"alg":"HS256","typ":"JWT"}' | openssl base64 -A | tr '+/' '-_' | tr -d '=')
  PAYLOAD=$(printf '{"role":"%s","iss":"supabase","iat":1735689600,"exp":2051222400}' "$ROLE" | openssl base64 -A | tr '+/' '-_' | tr -d '=')
  SIGN=$(printf '%s.%s' "$HEADER" "$PAYLOAD" | openssl dgst -sha256 -hmac "$JWT" -binary | openssl base64 -A | tr '+/' '-_' | tr -d '=')
  printf '%s.%s.%s' "$HEADER" "$PAYLOAD" "$SIGN"
}

NEW_ANON=$(generate_jwt "anon")
NEW_SRK=$(generate_jwt "service_role")

if [ -z "$NEW_ANON" ] || [ -z "$NEW_SRK" ]; then
  echo "❌ Falha ao gerar chaves JWT. Verifique se openssl está instalado."
  exit 1
fi

echo "   ✅ ANON_KEY gerada: ${NEW_ANON:0:30}..."
echo "   ✅ SERVICE_ROLE_KEY gerada: ${NEW_SRK:0:30}..."

# Atualizar .env
sed -i "s|^ANON_KEY=.*|ANON_KEY=\"${NEW_ANON}\"|" .env
sed -i "s|^SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=\"${NEW_SRK}\"|" .env

echo "   ✅ .env atualizado"

# Regenerar kong.yml com as novas chaves
if [ -f render-kong-config.sh ]; then
  echo "🔄 Renderizando kong.yml..."
  bash render-kong-config.sh
fi

# Recriar containers que dependem das chaves
echo "🔄 Reiniciando containers (kong, auth, rest, storage, functions)..."
docker compose up -d --force-recreate kong auth rest storage functions

# Aguardar auth ficar pronto
echo "⏳ Aguardando GoTrue iniciar..."
KONG_PORT=$(read_env "KONG_HTTP_PORT")
KONG_PORT="${KONG_PORT:-8000}"

for i in $(seq 1 30); do
  HTTP=$(curl -sS -o /dev/null -w "%{http_code}" \
    "http://127.0.0.1:${KONG_PORT}/auth/v1/health" 2>/dev/null || echo "000")
  [ "$HTTP" = "200" ] && break
  sleep 2
done

# Testar acesso admin API
echo "🧪 Testando SERVICE_ROLE_KEY..."
TEST_HTTP=$(curl -sS -o /tmp/fix-auth-test.json -w "%{http_code}" \
  -H "apikey: ${NEW_SRK}" \
  -H "Authorization: Bearer ${NEW_SRK}" \
  "http://127.0.0.1:${KONG_PORT}/auth/v1/admin/users" 2>/dev/null || echo "000")

if [ "$TEST_HTTP" != "200" ]; then
  echo "❌ Auth Admin API retornou HTTP $TEST_HTTP"
  cat /tmp/fix-auth-test.json 2>/dev/null || true
  echo ""
  echo "Tente: docker compose down && docker compose up -d"
  exit 1
fi

echo "   ✅ Auth Admin API OK (HTTP $TEST_HTTP)"

# Criar/atualizar admin
echo "👤 Criando admin ${ADMIN_EMAIL}..."
bash create-admin.sh "$ADMIN_EMAIL" "$ADMIN_PASSWORD"

# Rebuild frontend com nova ANON_KEY
echo "🔄 Reconstruindo frontend com nova ANON_KEY..."
docker compose up -d --build --force-recreate frontend

echo ""
echo "============================================"
echo "✅ Tudo corrigido!"
echo "   ANON_KEY:         ${NEW_ANON:0:30}..."
echo "   SERVICE_ROLE_KEY: ${NEW_SRK:0:30}..."
echo "   Admin:            ${ADMIN_EMAIL}"
echo "============================================"
echo "Acesse https://$(read_env 'SITE_DOMAIN')/admin para testar."
