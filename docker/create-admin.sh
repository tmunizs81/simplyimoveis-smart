#!/bin/bash
# ============================================================
# Cria o primeiro usuário admin
# Uso: bash create-admin.sh email@exemplo.com senha123
# ============================================================

set -euo pipefail

EMAIL=${1:-}
PASSWORD=${2:-}

if [ -z "$EMAIL" ] || [ -z "$PASSWORD" ]; then
  echo "Uso: bash create-admin.sh email@exemplo.com senha123"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source .env

# Usa a chave ativa do container Kong (evita mismatch com .env local)
RUNTIME_SERVICE_KEY=$(docker compose exec -T kong printenv SUPABASE_SERVICE_KEY 2>/dev/null | tr -d '\r' || true)
API_SERVICE_KEY="${RUNTIME_SERVICE_KEY:-${SERVICE_ROLE_KEY:-}}"

if [ -z "$API_SERVICE_KEY" ]; then
  echo "❌ SERVICE_ROLE_KEY não encontrada."
  exit 1
fi

if [ -n "$RUNTIME_SERVICE_KEY" ] && [ "${SERVICE_ROLE_KEY:-}" != "$RUNTIME_SERVICE_KEY" ]; then
  echo "⚠️  Detectado desencontro entre .env e chave ativa do Kong. Usando chave ativa do container."
fi

echo "👤 Criando usuário admin: ${EMAIL}..."

RESPONSE_WITH_STATUS=$(curl -sS -w "\n%{http_code}" -X POST "http://localhost:${KONG_HTTP_PORT:-8000}/auth/v1/admin/users" \
  -H "Authorization: Bearer ${API_SERVICE_KEY}" \
  -H "apikey: ${API_SERVICE_KEY}" \
  -H "Content-Type: application/json" \
  -d "{
    \"email\": \"${EMAIL}\",
    \"password\": \"${PASSWORD}\",
    \"email_confirm\": true
  }")

HTTP_STATUS=$(echo "$RESPONSE_WITH_STATUS" | tail -n1)
USER_RESPONSE=$(echo "$RESPONSE_WITH_STATUS" | sed '$d')

if [ "$HTTP_STATUS" -lt 200 ] || [ "$HTTP_STATUS" -ge 300 ]; then
  echo "❌ Erro ao criar usuário (HTTP $HTTP_STATUS):"
  echo "$USER_RESPONSE"
  if echo "$USER_RESPONSE" | grep -qi "Invalid authentication credentials"; then
    echo "💡 Dica: rode 'docker compose up -d --force-recreate kong auth rest storage functions' e tente novamente."
  fi
  exit 1
fi

USER_ID=$(echo "$USER_RESPONSE" | jq -r '.id // empty' 2>/dev/null)
if [ -z "$USER_ID" ]; then
  USER_ID=$(echo "$USER_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
fi

if [ -z "$USER_ID" ]; then
  echo "❌ Usuário criado sem ID retornado:"
  echo "$USER_RESPONSE"
  exit 1
fi

echo "✅ Usuário criado: ${USER_ID}"

# Adiciona role admin
docker exec simply-db psql -U supabase_admin -d ${POSTGRES_DB:-simply_db} -c \
  "INSERT INTO public.user_roles (user_id, role) VALUES ('${USER_ID}', 'admin') ON CONFLICT DO NOTHING;"

echo "✅ Role 'admin' atribuída."
echo ""
echo "🎉 Admin criado com sucesso!"
echo "   Email: ${EMAIL}"
echo "   Acesse: https://${SITE_DOMAIN}/admin"
