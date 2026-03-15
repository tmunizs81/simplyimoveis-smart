#!/bin/bash
# ============================================================
# Cria (ou atualiza) usuário admin de forma resiliente
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

read_env_var() {
  grep -E "^${1}=" .env 2>/dev/null | head -1 | sed "s/^${1}=//" | tr -d '"' | tr -d "'"
}

POSTGRES_DB=$(read_env_var "POSTGRES_DB")
POSTGRES_DB="${POSTGRES_DB:-simply_db}"
POSTGRES_PASSWORD=$(read_env_var "POSTGRES_PASSWORD")
KONG_PORT=$(read_env_var "KONG_HTTP_PORT")
KONG_PORT="${KONG_PORT:-8000}"
SERVICE_ROLE_KEY=$(read_env_var "SERVICE_ROLE_KEY")

if [ -z "$POSTGRES_PASSWORD" ]; then
  echo "❌ POSTGRES_PASSWORD não definido no .env"
  exit 1
fi

if [ -z "$SERVICE_ROLE_KEY" ] || [ "$SERVICE_ROLE_KEY" = "CHANGE_ME" ]; then
  echo "❌ SERVICE_ROLE_KEY inválida no .env"
  exit 1
fi

run_psql() {
  docker compose exec -T -e PGPASSWORD="${POSTGRES_PASSWORD}" db psql \
    -v ON_ERROR_STOP=1 \
    -U supabase_admin \
    -d "$POSTGRES_DB" \
    "$@" 2>/dev/null || \
  docker compose exec -T db psql \
    -v ON_ERROR_STOP=1 \
    -U postgres \
    -d "$POSTGRES_DB" \
    "$@"
}

wait_container_running() {
  local container="$1"
  local timeout="${2:-60}"

  for _ in $(seq 1 "$timeout"); do
    local state restarting
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
  for _ in {1..90}; do
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${KONG_PORT}/auth/v1/settings" \
      -H "apikey: ${api_key}" 2>/dev/null || echo "000")

    if [ "$status" = "200" ]; then
      return 0
    fi

    sleep 1
  done

  return 1
}

get_user_id_by_email() {
  run_psql -v user_email="$EMAIL" -tA -c "SELECT id FROM auth.users WHERE email = :'user_email' LIMIT 1;" | tr -d '[:space:]'
}

upsert_admin_direct_sql() {
  run_psql -v user_email="$EMAIL" -v user_password="$PASSWORD" <<'SQL'
CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
DECLARE
  v_user_id uuid;
BEGIN
  SELECT id INTO v_user_id
  FROM auth.users
  WHERE email = :'user_email'
  LIMIT 1;

  IF v_user_id IS NULL THEN
    INSERT INTO auth.users (
      id,
      instance_id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      raw_app_meta_data,
      raw_user_meta_data,
      created_at,
      updated_at
    )
    VALUES (
      gen_random_uuid(),
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      :'user_email',
      crypt(:'user_password', gen_salt('bf')),
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{}'::jsonb,
      now(),
      now()
    )
    RETURNING id INTO v_user_id;
  ELSE
    UPDATE auth.users
    SET encrypted_password = crypt(:'user_password', gen_salt('bf')),
        email_confirmed_at = COALESCE(email_confirmed_at, now()),
        aud = COALESCE(NULLIF(aud, ''), 'authenticated'),
        role = COALESCE(NULLIF(role, ''), 'authenticated'),
        raw_app_meta_data = COALESCE(raw_app_meta_data, '{"provider":"email","providers":["email"]}'::jsonb),
        raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb),
        updated_at = now()
    WHERE id = v_user_id;
  END IF;

  BEGIN
    INSERT INTO auth.identities (
      id,
      user_id,
      identity_data,
      provider,
      provider_id,
      created_at,
      updated_at,
      last_sign_in_at
    )
    VALUES (
      gen_random_uuid()::text,
      v_user_id,
      jsonb_build_object('sub', v_user_id::text, 'email', :'user_email'),
      'email',
      :'user_email',
      now(),
      now(),
      now()
    )
    ON CONFLICT (provider, provider_id) DO UPDATE
      SET user_id = EXCLUDED.user_id,
          identity_data = EXCLUDED.identity_data,
          updated_at = now();
  EXCEPTION
    WHEN undefined_column THEN
      INSERT INTO auth.identities (
        id,
        user_id,
        identity_data,
        provider,
        created_at,
        updated_at
      )
      VALUES (
        gen_random_uuid()::text,
        v_user_id,
        jsonb_build_object('sub', v_user_id::text, 'email', :'user_email'),
        'email',
        now(),
        now()
      )
      ON CONFLICT DO NOTHING;
  END;

  INSERT INTO public.user_roles (user_id, role)
  VALUES (v_user_id, 'admin')
  ON CONFLICT (user_id, role) DO NOTHING;
END
$$;
SQL
}

echo "🔧 Sincronizando banco e credenciais..."
docker compose up -d db >/dev/null 2>&1
bash "$SCRIPT_DIR/sync-db-passwords.sh" --quiet

# Corrige causa raiz: renderiza kong.yml com chaves reais
echo "🔑 Renderizando configuração do Kong..."
bash "$SCRIPT_DIR/render-kong-config.sh"

echo "🔄 Reiniciando serviços..."
docker compose up -d --force-recreate auth rest storage functions kong >/dev/null 2>&1

if ! wait_container_running simply-auth 90; then
  echo "❌ Container simply-auth não ficou estável."
  docker compose logs --tail=50 auth
  exit 1
fi

if ! wait_container_running simply-kong 90; then
  echo "❌ Container simply-kong não ficou estável."
  docker compose logs --tail=50 kong
  exit 1
fi

if ! wait_auth_ready "$SERVICE_ROLE_KEY"; then
  echo "❌ Auth não respondeu via Kong com a SERVICE_ROLE_KEY."
  echo "📋 Logs recentes de Kong:"
  docker compose logs --tail=60 kong
  exit 1
fi

echo "👤 Criando usuário admin: ${EMAIL}..."

RESPONSE_WITH_STATUS=$(curl -sS -w "\n%{http_code}" -X POST "http://localhost:${KONG_PORT}/auth/v1/admin/users" \
  -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" \
  -H "apikey: ${SERVICE_ROLE_KEY}" \
  -H "Content-Type: application/json" \
  -d "{
    \"email\": \"${EMAIL}\",
    \"password\": \"${PASSWORD}\",
    \"email_confirm\": true
  }" || printf "\n000")

HTTP_STATUS=$(echo "$RESPONSE_WITH_STATUS" | tail -n1)
USER_RESPONSE=$(echo "$RESPONSE_WITH_STATUS" | sed '$d')
USER_ID=""

if [ "$HTTP_STATUS" -ge 200 ] 2>/dev/null && [ "$HTTP_STATUS" -lt 300 ] 2>/dev/null; then
  if command -v jq >/dev/null 2>&1; then
    USER_ID=$(echo "$USER_RESPONSE" | jq -r '.id // .user.id // empty' 2>/dev/null || true)
  fi

  if [ -z "$USER_ID" ]; then
    USER_ID=$(echo "$USER_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4 || true)
  fi
else
  echo "⚠️  Auth API retornou HTTP ${HTTP_STATUS}. Aplicando fallback SQL resiliente..."
fi

if [ -z "$USER_ID" ]; then
  upsert_admin_direct_sql
  USER_ID=$(get_user_id_by_email)
fi

if [ -z "$USER_ID" ]; then
  echo "❌ Não foi possível obter o ID do usuário."
  exit 1
fi

echo "✅ Usuário pronto: ${USER_ID}"
echo "✅ Role 'admin' atribuída."
echo ""
echo "🎉 Admin criado/atualizado com sucesso!"
echo "   Email: ${EMAIL}"
SITE_DOMAIN=$(read_env_var "SITE_DOMAIN")
echo "   Acesse: https://${SITE_DOMAIN:-localhost}/admin"