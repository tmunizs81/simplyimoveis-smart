#!/bin/bash
# ============================================================
# fix-vps-admin.sh — Script de correção completa do admin panel
# para ambiente self-hosted VPS com PostgreSQL
# 
# O que faz:
# 1. Verifica conexão com banco
# 2. Garante que todas as tabelas existem com schema correto
# 3. Corrige todas as RLS policies (WITH CHECK explícito)
# 4. Garante has_role() function existe
# 5. Garante roles e grants corretos
# 6. Sincroniza edge functions (incluindo admin-crud)
# 7. Verifica .env tem todas as variáveis necessárias
#
# Uso: cd /opt/simply-imoveis/docker && sudo bash fix-vps-admin.sh
# Versão: 2026-03-15-v1
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "  Simply Imóveis — Correção VPS Admin"
echo "=========================================="

# ── Pré-requisitos ──
[ ! -f .env ] && echo "❌ .env não encontrado em $SCRIPT_DIR" && exit 1

read_env() { grep -E "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"; }

POSTGRES_PASSWORD=$(read_env "POSTGRES_PASSWORD")
POSTGRES_DB=$(read_env "POSTGRES_DB"); POSTGRES_DB="${POSTGRES_DB:-simply_db}"
DB_CONTAINER="simply-db"

[ -z "${POSTGRES_PASSWORD:-}" ] && echo "❌ POSTGRES_PASSWORD vazio no .env" && exit 1

# ── 1. Verificar container DB ──
echo ""
echo "1️⃣  Verificando container de banco..."
DB_STATUS=$(docker inspect -f '{{.State.Status}}' "$DB_CONTAINER" 2>/dev/null || echo "not_found")
[ "$DB_STATUS" != "running" ] && echo "❌ Container $DB_CONTAINER não rodando ($DB_STATUS)" && exit 1
echo "   ✅ Container $DB_CONTAINER rodando"

# ── Encontrar superuser ──
DB_USER=""
for candidate in "$(read_env "POSTGRES_USER")" supabase_admin postgres; do
  [ -z "$candidate" ] && continue
  RESULT=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
    psql -tA -w -h 127.0.0.1 -U "$candidate" -d "$POSTGRES_DB" -c "SELECT 1" 2>/dev/null || true)
  if [ "$RESULT" = "1" ]; then DB_USER="$candidate"; break; fi
done

if [ -z "$DB_USER" ]; then
  echo "   ⏳ Aguardando banco..."
  for i in {1..20}; do
    for candidate in supabase_admin postgres; do
      RESULT=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
        psql -tA -w -h 127.0.0.1 -U "$candidate" -d "$POSTGRES_DB" -c "SELECT 1" 2>/dev/null || true)
      [ "$RESULT" = "1" ] && DB_USER="$candidate" && break 2
    done
    sleep 2
  done
fi

[ -z "$DB_USER" ] && echo "❌ Não foi possível conectar ao PostgreSQL" && exit 1
echo "   ✅ Conectado como $DB_USER"

R() {
  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
    psql -v ON_ERROR_STOP=0 -w -h 127.0.0.1 -U "$DB_USER" -d "$POSTGRES_DB" -c "$1" 2>&1 || true
}

ESCAPED_PASS=$(printf '%s' "$POSTGRES_PASSWORD" | sed "s/'/''/g")

# ── 2. Verificar/criar enum e function ──
echo ""
echo "2️⃣  Verificando enum app_role e função has_role..."

R "DO \$\$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'app_role') THEN
    CREATE TYPE public.app_role AS ENUM ('admin', 'moderator', 'user');
  END IF;
END \$\$;" >/dev/null

R "CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role app_role)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS \$\$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role)
\$\$;" >/dev/null

R "GRANT EXECUTE ON FUNCTION public.has_role(uuid, app_role) TO anon, authenticated, service_role, authenticator;" >/dev/null
echo "   ✅ has_role() criada/atualizada"

# ── 3. Corrigir TODAS as RLS policies ──
echo ""
echo "3️⃣  Corrigindo RLS policies..."

# Tabelas com policy FOR ALL de admin
ADMIN_TABLES=(
  "tenants:Admins can manage tenants"
  "leads:Admins can manage leads"
  "sales:Admins can manage sales"
  "rental_contracts:Admins can manage contracts"
  "financial_transactions:Admins can manage transactions"
  "property_inspections:Admins can manage inspections"
  "inspection_media:Admins can manage inspection media"
  "contract_documents:Admins can manage documents"
  "tenant_documents:Admins can manage tenant docs"
  "sales_documents:Admins can manage sale docs"
  "properties:Admins can manage properties"
  "property_media:Admins can manage property media"
  "property_code_sequences:Admins can manage code sequences"
)

for entry in "${ADMIN_TABLES[@]}"; do
  IFS=':' read -r tbl policy_name <<< "$entry"
  
  # Drop existing policy (may have missing WITH CHECK)
  R "DROP POLICY IF EXISTS \"$policy_name\" ON public.$tbl;" >/dev/null
  
  # Recreate with explicit WITH CHECK
  R "ALTER TABLE public.$tbl ENABLE ROW LEVEL SECURITY;" >/dev/null
  R "CREATE POLICY \"$policy_name\" ON public.$tbl FOR ALL TO authenticated
    USING (public.has_role(auth.uid(), 'admin'::app_role))
    WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));" >/dev/null
  
  echo "   ✅ $tbl — policy corrigida"
done

# Policies públicas (não admin)
echo "   Verificando policies públicas..."
R "DROP POLICY IF EXISTS \"Anyone can view active properties\" ON public.properties;" >/dev/null
R "CREATE POLICY \"Anyone can view active properties\" ON public.properties FOR SELECT TO public USING (active = true);" >/dev/null

R "DROP POLICY IF EXISTS \"Anyone can view property media\" ON public.property_media;" >/dev/null
R "CREATE POLICY \"Anyone can view property media\" ON public.property_media FOR SELECT TO public USING (true);" >/dev/null

R "DROP POLICY IF EXISTS \"Anyone can submit contact\" ON public.contact_submissions;" >/dev/null
R "CREATE POLICY \"Anyone can submit contact\" ON public.contact_submissions FOR INSERT TO public WITH CHECK (true);" >/dev/null

R "DROP POLICY IF EXISTS \"Anyone can insert visits\" ON public.scheduled_visits;" >/dev/null
R "CREATE POLICY \"Anyone can insert visits\" ON public.scheduled_visits FOR INSERT TO public WITH CHECK (true);" >/dev/null

# user_roles policies
for pol in "Admins can view roles" "Admins can insert roles" "Admins can update roles" "Admins can delete roles" "Users can view own role"; do
  R "DROP POLICY IF EXISTS \"$pol\" ON public.user_roles;" >/dev/null
done
R "ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;" >/dev/null
R "CREATE POLICY \"Admins can view roles\" ON public.user_roles FOR SELECT TO authenticated USING (true);" >/dev/null
R "CREATE POLICY \"Admins can insert roles\" ON public.user_roles FOR INSERT TO authenticated WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));" >/dev/null
R "CREATE POLICY \"Admins can update roles\" ON public.user_roles FOR UPDATE TO authenticated USING (public.has_role(auth.uid(), 'admin'::app_role)) WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));" >/dev/null
R "CREATE POLICY \"Admins can delete roles\" ON public.user_roles FOR DELETE TO authenticated USING (public.has_role(auth.uid(), 'admin'::app_role));" >/dev/null
R "CREATE POLICY \"Users can view own role\" ON public.user_roles FOR SELECT TO authenticated USING (auth.uid() = user_id);" >/dev/null
echo "   ✅ user_roles — policies corrigidas"

# Contact submissions specific policies
for pol in "Admins can view contacts" "Admins can update contacts" "Admins can delete contacts"; do
  R "DROP POLICY IF EXISTS \"$pol\" ON public.contact_submissions;" >/dev/null
done
R "CREATE POLICY \"Admins can view contacts\" ON public.contact_submissions FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'::app_role));" >/dev/null
R "CREATE POLICY \"Admins can update contacts\" ON public.contact_submissions FOR UPDATE TO authenticated USING (public.has_role(auth.uid(), 'admin'::app_role));" >/dev/null
R "CREATE POLICY \"Admins can delete contacts\" ON public.contact_submissions FOR DELETE TO authenticated USING (public.has_role(auth.uid(), 'admin'::app_role));" >/dev/null

# Scheduled visits specific policies
for pol in "Admins can view visits" "Admins can update visits" "Admins can delete visits"; do
  R "DROP POLICY IF EXISTS \"$pol\" ON public.scheduled_visits;" >/dev/null
done
R "CREATE POLICY \"Admins can view visits\" ON public.scheduled_visits FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'::app_role));" >/dev/null
R "CREATE POLICY \"Admins can update visits\" ON public.scheduled_visits FOR UPDATE TO authenticated USING (public.has_role(auth.uid(), 'admin'::app_role));" >/dev/null
R "CREATE POLICY \"Admins can delete visits\" ON public.scheduled_visits FOR DELETE TO authenticated USING (public.has_role(auth.uid(), 'admin'::app_role));" >/dev/null

echo "   ✅ Todas as policies públicas verificadas"

# ── 4. Grants ──
echo ""
echo "4️⃣  Aplicando grants..."
R "GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role, authenticator;" >/dev/null
R "GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;" >/dev/null
R "GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;" >/dev/null
R "GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO anon, authenticated, service_role;" >/dev/null
R "ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;" >/dev/null
R "ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;" >/dev/null
R "ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;" >/dev/null
echo "   ✅ Grants aplicados"

# ── 5. Senhas ──
echo ""
echo "5️⃣  Sincronizando senhas..."
for role in postgres supabase_admin supabase_auth_admin supabase_storage_admin authenticator; do
  R "ALTER ROLE $role WITH PASSWORD '${ESCAPED_PASS}';" >/dev/null
done
R "GRANT anon TO authenticator;" >/dev/null
R "GRANT authenticated TO authenticator;" >/dev/null
R "GRANT service_role TO authenticator;" >/dev/null
echo "   ✅ Senhas sincronizadas"

# ── 6. Auth functions ──
echo ""
echo "6️⃣  Recriando funções auth..."
R "CREATE SCHEMA IF NOT EXISTS auth AUTHORIZATION supabase_auth_admin;" >/dev/null

docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
  psql -v ON_ERROR_STOP=0 -w -h 127.0.0.1 -U supabase_auth_admin -d "$POSTGRES_DB" <<'EOSQL' >/dev/null 2>&1
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid,
    NULLIF((NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'), '')::uuid
  );
$$;
CREATE OR REPLACE FUNCTION auth.role()
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claim.role', true), '')::text,
    NULLIF((NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'), '')::text
  );
$$;
CREATE OR REPLACE FUNCTION auth.email()
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claim.email', true), '')::text,
    NULLIF((NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email'), '')::text
  );
$$;
EOSQL

R "GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated, service_role, authenticator;" >/dev/null
R "GRANT EXECUTE ON FUNCTION auth.role() TO anon, authenticated, service_role, authenticator;" >/dev/null
R "GRANT EXECUTE ON FUNCTION auth.email() TO anon, authenticated, service_role, authenticator;" >/dev/null
echo "   ✅ Funções auth recriadas"

# ── 7. Sincronizar Edge Functions ──
echo ""
echo "7️⃣  Sincronizando Edge Functions..."
if [ -f sync-functions.sh ]; then
  bash sync-functions.sh
else
  echo "   ⚠️ sync-functions.sh não encontrado, verificando manualmente..."
  if [ -d volumes/functions/admin-crud ]; then
    echo "   ✅ admin-crud já existe"
  else
    echo "   ❌ admin-crud NÃO existe — rode update-from-github.sh primeiro"
  fi
fi

# ── 8. Verificar .env ──
echo ""
echo "8️⃣  Verificando variáveis de ambiente..."
MISSING=""
for var in SITE_DOMAIN POSTGRES_PASSWORD JWT_SECRET ANON_KEY SERVICE_ROLE_KEY; do
  val=$(read_env "$var")
  if [ -z "$val" ] || [ "$val" = "CHANGE_ME" ]; then
    MISSING="$MISSING $var"
  fi
done
if [ -n "$MISSING" ]; then
  echo "   ⚠️ Variáveis faltando ou com valor padrão:$MISSING"
else
  echo "   ✅ Todas as variáveis essenciais configuradas"
fi

# ── 9. Verificação final ──
echo ""
echo "9️⃣  Verificação final..."

# Check policies have WITH CHECK
MISSING_CHECK=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
  psql -tA -w -h 127.0.0.1 -U "$DB_USER" -d "$POSTGRES_DB" \
  -c "SELECT tablename || '.' || policyname FROM pg_policies WHERE cmd='ALL' AND with_check IS NULL AND schemaname='public';" 2>/dev/null || true)

if [ -n "$MISSING_CHECK" ] && [ "$MISSING_CHECK" != "" ]; then
  echo "   ⚠️ Policies FOR ALL sem WITH CHECK encontradas:"
  echo "$MISSING_CHECK" | while read line; do
    [ -n "$line" ] && echo "      - $line"
  done
else
  echo "   ✅ Todas as policies FOR ALL têm WITH CHECK"
fi

# Check admin user exists
ADMIN_COUNT=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_CONTAINER" \
  psql -tA -w -h 127.0.0.1 -U "$DB_USER" -d "$POSTGRES_DB" \
  -c "SELECT count(*) FROM public.user_roles WHERE role='admin';" 2>/dev/null || echo "0")
ADMIN_COUNT=$(echo "$ADMIN_COUNT" | tr -d '[:space:]')

if [ "$ADMIN_COUNT" = "0" ]; then
  echo "   ⚠️ Nenhum admin encontrado! Rode: bash create-admin.sh"
else
  echo "   ✅ $ADMIN_COUNT admin(s) configurado(s)"
fi

echo ""
echo "=========================================="
echo "  ✅ Correção concluída!"
echo "=========================================="
echo ""
echo "Próximos passos:"
echo "  1. docker compose restart"
echo "  2. Teste o login em /admin"
echo "  3. Teste criar um inquilino"
echo "  4. Teste todas as seções do admin"
echo ""
