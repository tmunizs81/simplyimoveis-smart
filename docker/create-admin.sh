#!/bin/bash
# ============================================================
# Cria o primeiro usuário admin (via banco direto - sem API)
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

if [ -z "$POSTGRES_PASSWORD" ]; then
  echo "❌ POSTGRES_PASSWORD não definido no .env"
  exit 1
fi

# Helper para rodar psql sem prompt de senha
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

# Garantir DB rodando
echo "🔧 Verificando banco..."
docker compose up -d db >/dev/null 2>&1

for _ in {1..30}; do
  DB_HEALTH=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' simply-db 2>/dev/null || true)
  if [ "$DB_HEALTH" = "healthy" ]; then break; fi
  sleep 2
done

if [ "$DB_HEALTH" != "healthy" ]; then
  echo "❌ Banco não ficou saudável."
  exit 1
fi

# Sincronizar senhas
bash "$SCRIPT_DIR/sync-db-passwords.sh" --quiet

echo "👤 Criando usuário admin: ${EMAIL}..."

# Gerar UUID
USER_UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())")

# Hash da senha usando crypt (bcrypt via pgcrypto)
# GoTrue usa bcrypt, e o Supabase postgres tem pgcrypto
USER_ID=$(run_psql -tA <<SQL
DO \$\$
DECLARE
  v_user_id uuid;
BEGIN
  -- Verifica se já existe
  SELECT id INTO v_user_id FROM auth.users WHERE email = '${EMAIL}';
  
  IF v_user_id IS NOT NULL THEN
    RAISE NOTICE 'EXISTING:%', v_user_id;
    RETURN;
  END IF;

  -- Cria o usuário diretamente na tabela auth.users
  INSERT INTO auth.users (
    id,
    instance_id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    confirmation_sent_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
  ) VALUES (
    '${USER_UUID}',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    '${EMAIL}',
    crypt('${PASSWORD}', gen_salt('bf')),
    now(),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{}',
    now(),
    now()
  );

  -- Cria identidade
  INSERT INTO auth.identities (
    id,
    user_id,
    provider_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
  ) VALUES (
    gen_random_uuid(),
    '${USER_UUID}',
    '${EMAIL}',
    jsonb_build_object('sub', '${USER_UUID}', 'email', '${EMAIL}'),
    'email',
    now(),
    now(),
    now()
  );

  RAISE NOTICE 'CREATED:%', '${USER_UUID}';
END
\$\$;
SQL
)

# Extrai o ID do output
FINAL_ID=$(echo "$USER_ID" | grep -oP '(?:EXISTING|CREATED):(.+)' | head -1 | cut -d: -f2 || true)

if [ -z "$FINAL_ID" ]; then
  # Busca direto
  FINAL_ID=$(run_psql -tA -c "SELECT id FROM auth.users WHERE email = '${EMAIL}' LIMIT 1;" | tr -d '[:space:]')
fi

if [ -z "$FINAL_ID" ]; then
  echo "❌ Não foi possível criar/encontrar o usuário."
  exit 1
fi

echo "✅ Usuário pronto: ${FINAL_ID}"

# Adiciona role admin
run_psql -c "INSERT INTO public.user_roles (user_id, role) VALUES ('${FINAL_ID}', 'admin') ON CONFLICT DO NOTHING;"

echo "✅ Role 'admin' atribuída."
echo ""
echo "🎉 Admin criado com sucesso!"
echo "   Email: ${EMAIL}"

SITE_DOMAIN=$(read_env_var "SITE_DOMAIN")
echo "   Acesse: https://${SITE_DOMAIN:-localhost}/admin"
