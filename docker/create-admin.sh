#!/bin/bash
# ============================================================
# Cria ou atualiza admin via SQL direto (100% idempotente)
# Uso: bash create-admin.sh email senha
# Versão: 2026-03-15-v9
# ============================================================

set -euo pipefail

EMAIL="${1:-}"
PASSWORD="${2:-}"

[ -z "$EMAIL" ] || [ -z "$PASSWORD" ] && echo "Uso: bash create-admin.sh email senha" && exit 1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

[ ! -f .env ] && echo "❌ .env não encontrado" && exit 1

POSTGRES_DB=$(grep -E '^POSTGRES_DB=' .env | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
POSTGRES_DB="${POSTGRES_DB:-simply_db}"
POSTGRES_PASSWORD=$(grep -E '^POSTGRES_PASSWORD=' .env | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
DB_CONTAINER="simply-db"

[ -z "${POSTGRES_PASSWORD:-}" ] && echo "❌ POSTGRES_PASSWORD vazio" && exit 1

docker inspect -f '{{.State.Status}}' "$DB_CONTAINER" >/dev/null 2>&1 || { echo "❌ Container $DB_CONTAINER não encontrado"; exit 1; }

run_sql_cmd() {
  timeout 30s docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" \
    "$DB_CONTAINER" psql -v ON_ERROR_STOP=1 -w -h 127.0.0.1 -U supabase_admin -d "$POSTGRES_DB" "$@"
}

run_sql_stdin() {
  timeout 30s docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" \
    "$DB_CONTAINER" psql -v ON_ERROR_STOP=1 -w -h 127.0.0.1 -U supabase_admin -d "$POSTGRES_DB" "$@"
}

# Verifica se auth.users existe
AUTH_OK=$(run_sql -tA -c "SELECT to_regclass('auth.users') IS NOT NULL;" 2>/dev/null | tr -d '[:space:]')
if [ "$AUTH_OK" != "t" ]; then
  echo "❌ auth.users não existe. GoTrue ainda não migrou."
  echo "   Aguarde mais 30s e tente novamente."
  exit 1
fi

echo "👤 Criando admin: ${EMAIL}..."

SAFE_PASS=$(printf '%s' "$PASSWORD" | sed "s/'/''/g")

run_sql <<EOSQL
CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO \$\$
DECLARE
  v_uid uuid;
BEGIN
  SELECT id INTO v_uid FROM auth.users WHERE email = '${EMAIL}' LIMIT 1;

  IF v_uid IS NULL THEN
    INSERT INTO auth.users (
      id, instance_id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at, confirmation_token, recovery_token
    ) VALUES (
      gen_random_uuid(), '00000000-0000-0000-0000-000000000000',
      'authenticated', 'authenticated', '${EMAIL}',
      crypt('${SAFE_PASS}', gen_salt('bf')),
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{}'::jsonb,
      now(), now(), '', ''
    ) RETURNING id INTO v_uid;
    RAISE NOTICE 'Usuário criado: %', v_uid;
  ELSE
    UPDATE auth.users SET
      encrypted_password = crypt('${SAFE_PASS}', gen_salt('bf')),
      email_confirmed_at = COALESCE(email_confirmed_at, now()),
      aud = 'authenticated', role = 'authenticated',
      raw_app_meta_data = COALESCE(raw_app_meta_data, '{"provider":"email","providers":["email"]}'::jsonb),
      updated_at = now()
    WHERE id = v_uid;
    RAISE NOTICE 'Usuário atualizado: %', v_uid;
  END IF;

  INSERT INTO auth.identities (id, user_id, identity_data, provider, provider_id, created_at, updated_at, last_sign_in_at)
  VALUES (
    v_uid, v_uid,
    jsonb_build_object('sub', v_uid::text, 'email', '${EMAIL}'),
    'email', '${EMAIL}', now(), now(), now()
  )
  ON CONFLICT (provider, provider_id) DO UPDATE SET
    user_id = EXCLUDED.user_id,
    identity_data = EXCLUDED.identity_data,
    updated_at = now();

  INSERT INTO public.user_roles (user_id, role) VALUES (v_uid, 'admin')
  ON CONFLICT (user_id, role) DO NOTHING;

  RAISE NOTICE '✅ Admin pronto: % (%)', '${EMAIL}', v_uid;
END \$\$;
EOSQL

echo "✅ Admin ${EMAIL} configurado com sucesso!"
