#!/bin/bash
# ============================================================
# Cria ou atualiza usuário admin via SQL direto (sem depender da Auth API)
# Uso: bash create-admin.sh email@exemplo.com senha123
# Versão: 2026-03-15-v3-sql-only
# ============================================================

set -euo pipefail

EMAIL=${1:-}
PASSWORD=${2:-}

[ -z "$EMAIL" ] || [ -z "$PASSWORD" ] && echo "Uso: bash create-admin.sh email senha" && exit 1

echo "ℹ️  create-admin.sh versão: 2026-03-15-v3-sql-only"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

[ ! -f .env ] && echo "❌ .env não encontrado." && exit 1

read_env_var() {
  grep -E "^${1}=" .env 2>/dev/null | head -1 | sed "s/^${1}=//" | tr -d '"' | tr -d "'"
}

POSTGRES_DB=$(read_env_var "POSTGRES_DB")
POSTGRES_DB="${POSTGRES_DB:-simply_db}"
POSTGRES_PASSWORD=$(read_env_var "POSTGRES_PASSWORD")

[ -z "$POSTGRES_PASSWORD" ] && echo "❌ POSTGRES_PASSWORD não definido" && exit 1

run_psql() {
  docker compose exec -T -e PGPASSWORD="${POSTGRES_PASSWORD}" db psql \
    -v ON_ERROR_STOP=1 -U supabase_admin -d "$POSTGRES_DB" "$@" 2>/dev/null || \
  docker compose exec -T db psql \
    -v ON_ERROR_STOP=1 -U postgres -d "$POSTGRES_DB" "$@"
}

echo "🔧 Garantindo banco rodando..."
docker compose up -d db >/dev/null 2>&1

for _ in {1..30}; do
  DB_HEALTH=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' simply-db 2>/dev/null || true)
  [ "$DB_HEALTH" = "healthy" ] && break
  sleep 2
done

AUTH_USERS_EXISTS=$(run_psql -tA -c "SELECT to_regclass('auth.users') IS NOT NULL;" | tr -d '[:space:]')
if [ "$AUTH_USERS_EXISTS" != "t" ]; then
  echo "❌ auth.users não existe. Rode: bash sync-db-passwords.sh && docker compose restart auth"
  exit 1
fi

echo "👤 Criando/atualizando admin: ${EMAIL}..."

TMP_SQL=$(mktemp /tmp/create-admin-XXXXXX.sql)
cat > "$TMP_SQL" << 'EOSQL'
CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
DECLARE
  v_user_id uuid;
  v_email text := current_setting('app.admin_email');
  v_pass  text := current_setting('app.admin_pass');
BEGIN
  SELECT id INTO v_user_id FROM auth.users WHERE email = v_email LIMIT 1;

  IF v_user_id IS NULL THEN
    INSERT INTO auth.users (
      id, instance_id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at, confirmation_token, recovery_token
    ) VALUES (
      gen_random_uuid(),
      '00000000-0000-0000-0000-000000000000',
      'authenticated', 'authenticated', v_email,
      crypt(v_pass, gen_salt('bf')),
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{}'::jsonb,
      now(), now(), '', ''
    ) RETURNING id INTO v_user_id;

    RAISE NOTICE 'Usuário criado: %', v_user_id;
  ELSE
    UPDATE auth.users SET
      encrypted_password = crypt(v_pass, gen_salt('bf')),
      email_confirmed_at = COALESCE(email_confirmed_at, now()),
      aud = 'authenticated',
      role = 'authenticated',
      raw_app_meta_data = COALESCE(raw_app_meta_data, '{"provider":"email","providers":["email"]}'::jsonb),
      updated_at = now()
    WHERE id = v_user_id;

    RAISE NOTICE 'Usuário atualizado: %', v_user_id;
  END IF;

  -- Identity (idempotente)
  INSERT INTO auth.identities (id, user_id, identity_data, provider, provider_id, created_at, updated_at, last_sign_in_at)
  VALUES (
    v_user_id,
    v_user_id,
    jsonb_build_object('sub', v_user_id::text, 'email', v_email),
    'email', v_email, now(), now(), now()
  )
  ON CONFLICT (provider, provider_id) DO UPDATE SET
    user_id = EXCLUDED.user_id,
    identity_data = EXCLUDED.identity_data,
    updated_at = now();

  -- Role admin
  INSERT INTO public.user_roles (user_id, role)
  VALUES (v_user_id, 'admin')
  ON CONFLICT (user_id, role) DO NOTHING;

  RAISE NOTICE '✅ Admin pronto: % (%)', v_email, v_user_id;
END $$;
EOSQL

docker compose exec -T \
  -e PGPASSWORD="${POSTGRES_PASSWORD}" \
  -e PGOPTIONS="-c app.admin_email=${EMAIL} -c app.admin_pass=${PASSWORD}" \
  db psql -v ON_ERROR_STOP=1 -U supabase_admin -d "$POSTGRES_DB" -f - < "$TMP_SQL" || {
  echo "⚠️  Tentando com usuário postgres..."
  docker compose exec -T \
    -e PGOPTIONS="-c app.admin_email=${EMAIL} -c app.admin_pass=${PASSWORD}" \
    db psql -v ON_ERROR_STOP=1 -U postgres -d "$POSTGRES_DB" -f - < "$TMP_SQL"
}

rm -f "$TMP_SQL"

USER_ID=$(run_psql -tA -c "SELECT id FROM auth.users WHERE email = '${EMAIL}' LIMIT 1;" | tr -d '[:space:]')

if [ -z "$USER_ID" ]; then
  echo "❌ Falha ao criar usuário."
  exit 1
fi

echo "✅ Admin: ${EMAIL} (${USER_ID})"
echo "✅ Role 'admin' atribuída."
SITE_DOMAIN=$(read_env_var "SITE_DOMAIN")
echo "🎉 Acesse: https://${SITE_DOMAIN:-localhost}/admin"