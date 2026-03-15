#!/bin/bash
# ============================================================
# Cria o primeiro usuário admin (resiliente)
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

if [ ! -f .env ]; then
  echo "❌ Arquivo .env não encontrado."
  exit 1
fi

set -a
source .env
set +a

POSTGRES_DB="${POSTGRES_DB:-simply_db}"
KONG_PORT="${KONG_HTTP_PORT:-8000}"

wait_container_running() {
  local container="$1"
  local timeout="${2:-60}"

  for _ in $(seq 1 "$timeout"); do
    local state
    local restarting
    state=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || true)
    restarting=$(docker inspect -f '{{.State.Restarting}}' "$container" 2>/dev/null || true)

    if [ "$state" = "running" ] && [ "$restarting" != "true" ]; then
      return 0
    fi

    sleep 1
  done

  return 1
}

wait_auth_ready() {
  local api_key="$1"
  for _ in {1..60}; do
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${KONG_PORT}/auth/v1/settings" \
      -H "apikey: ${api_key}" || true)

    if [ "$status" = "200" ]; then
      return 0
    fi

    sleep 1
  done

  return 1
}

# 1) Garantir DB + roles internos sincronizados
docker compose up -d db >/dev/null
bash "$SCRIPT_DIR/sync-db-passwords.sh" --quiet

# 2) Recriar serviços dependentes para usar senha atualizada
docker compose up -d --force-recreate auth rest storage functions kong >/dev/null

if ! wait_container_running simply-auth 90; then
  echo "❌ Container simply-auth não ficou estável."
  docker compose logs --tail=120 auth
  exit 1
fi

if ! wait_container_running simply-kong 60; then
  echo "❌ Container simply-kong não ficou estável."
  docker compose logs --tail=120 kong
  exit 1
fi

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

if ! wait_auth_ready "$API_SERVICE_KEY"; then
  echo "❌ Auth não respondeu corretamente após sincronização."
  echo "📋 Logs recentes (auth/rest/storage):"
  docker compose logs --tail=120 auth rest storage
  exit 1
fi

echo "👤 Criando usuário admin: ${EMAIL}..."

RESPONSE_WITH_STATUS=$(curl -sS -w "\n%{http_code}" -X POST "http://localhost:${KONG_PORT}/auth/v1/admin/users" \
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

USER_ID=""

if [ "$HTTP_STATUS" -ge 200 ] && [ "$HTTP_STATUS" -lt 300 ]; then
  USER_ID=$(echo "$USER_RESPONSE" | jq -r '.id // .user.id // empty' 2>/dev/null || true)
  if [ -z "$USER_ID" ]; then
    USER_ID=$(echo "$USER_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4 || true)
  fi
else
  echo "❌ Erro ao criar usuário (HTTP $HTTP_STATUS):"
  echo "$USER_RESPONSE"

  if echo "$USER_RESPONSE" | grep -qi "already been registered\|already exists"; then
    echo "ℹ️  Usuário já existe, buscando ID para apenas atribuir role admin..."
  else
    if echo "$USER_RESPONSE" | grep -qi "Invalid authentication credentials"; then
      echo "💡 Dica: execute 'bash sync-db-passwords.sh' e tente novamente."
    fi
    exit 1
  fi
fi

if [ -z "$USER_ID" ]; then
  USER_ID=$(docker compose exec -T db psql \
    -v ON_ERROR_STOP=1 \
    -U supabase_admin \
    -d "$POSTGRES_DB" \
    -v user_email="$EMAIL" \
    -tA -c "SELECT id FROM auth.users WHERE email = :'user_email' LIMIT 1;" | tr -d '[:space:]')
fi

if [ -z "$USER_ID" ]; then
  echo "❌ Não foi possível obter o ID do usuário."
  exit 1
fi

echo "✅ Usuário pronto: ${USER_ID}"

# Adiciona role admin
docker compose exec -T db psql \
  -v ON_ERROR_STOP=1 \
  -U supabase_admin \
  -d "$POSTGRES_DB" \
  -v user_id="$USER_ID" \
  -c "INSERT INTO public.user_roles (user_id, role) VALUES (:'user_id', 'admin') ON CONFLICT DO NOTHING;"

echo "✅ Role 'admin' atribuída."
echo ""
echo "🎉 Admin criado com sucesso!"
echo "   Email: ${EMAIL}"
echo "   Acesse: https://${SITE_DOMAIN}/admin"
