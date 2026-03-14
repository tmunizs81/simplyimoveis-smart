#!/bin/bash
# ============================================================
# Cria o primeiro usuário admin
# Uso: bash create-admin.sh email@exemplo.com senha123
# ============================================================

set -e

EMAIL=${1}
PASSWORD=${2}

if [ -z "$EMAIL" ] || [ -z "$PASSWORD" ]; then
  echo "Uso: bash create-admin.sh email@exemplo.com senha123"
  exit 1
fi

source .env

echo "👤 Criando usuário admin: ${EMAIL}..."

# Cria usuário via GoTrue
USER_RESPONSE=$(curl -s -X POST "http://localhost:${KONG_HTTP_PORT:-8000}/auth/v1/admin/users" \
  -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" \
  -H "apikey: ${SERVICE_ROLE_KEY}" \
  -H "Content-Type: application/json" \
  -d "{
    \"email\": \"${EMAIL}\",
    \"password\": \"${PASSWORD}\",
    \"email_confirm\": true
  }")

USER_ID=$(echo "$USER_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$USER_ID" ]; then
  echo "❌ Erro ao criar usuário:"
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
