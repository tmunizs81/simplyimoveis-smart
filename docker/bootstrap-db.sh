#!/bin/bash
# ============================================================
# Bootstrap completo do banco (pipeline com dependências)
# Ordem: extensões -> tipos -> tabelas -> funções -> dados -> buckets -> policies
# Uso: bash bootstrap-db.sh
# ============================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

[ ! -f .env ] && echo -e "${RED}❌ .env não encontrado${NC}" && exit 1
[ ! -f sql/selfhosted-admin-recovery.sql ] && echo -e "${RED}❌ sql/selfhosted-admin-recovery.sql não encontrado${NC}" && exit 1
[ ! -f sql/bootstrap-storage.sql ] && echo -e "${RED}❌ sql/bootstrap-storage.sql não encontrado${NC}" && exit 1
[ ! -f sync-db-passwords.sh ] && echo -e "${RED}❌ sync-db-passwords.sh não encontrado${NC}" && exit 1
[ ! -f ensure-storage-buckets.sh ] && echo -e "${RED}❌ ensure-storage-buckets.sh não encontrado${NC}" && exit 1

read_env() { grep -E "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"; }

POSTGRES_PASSWORD=$(read_env "POSTGRES_PASSWORD")
POSTGRES_DB=$(read_env "POSTGRES_DB"); POSTGRES_DB="${POSTGRES_DB:-simply_db}"
DB_ADMIN_USER=$(read_env "POSTGRES_USER"); DB_ADMIN_USER="${DB_ADMIN_USER:-supabase_admin}"

[ -z "${POSTGRES_PASSWORD:-}" ] && echo -e "${RED}❌ POSTGRES_PASSWORD vazio${NC}" && exit 1

echo -e "${BLUE}⏳ Aguardando PostgreSQL...${NC}"
for i in {1..60}; do
  if docker exec simply-db pg_isready -U "$DB_ADMIN_USER" -d "$POSTGRES_DB" -q 2>/dev/null; then
    break
  fi
  [ "$i" = "60" ] && echo -e "${RED}❌ PostgreSQL não respondeu em 120s${NC}" && exit 1
  sleep 2
done
echo -e "   ${GREEN}✅ PostgreSQL pronto${NC}"

echo -e "${BLUE}🔐 Sincronizando funções auth.uid()/auth.role()/auth.email()...${NC}"
bash sync-db-passwords.sh

echo -e "${BLUE}🧱 Aplicando bootstrap core (schema/rls/funções)...${NC}"
docker compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" db \
  psql -v ON_ERROR_STOP=1 -w -h 127.0.0.1 -U "$DB_ADMIN_USER" -d "$POSTGRES_DB" -f sql/selfhosted-admin-recovery.sql

echo -e "${BLUE}🔎 Validando dependências do pipeline...${NC}"
CORE_OK=$(docker compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" db \
  psql -tA -w -h 127.0.0.1 -U "$DB_ADMIN_USER" -d "$POSTGRES_DB" -c "
  SELECT CASE WHEN
    to_regclass('public.user_roles') IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM pg_type t
      JOIN pg_namespace n ON n.oid = t.typnamespace
      WHERE n.nspname = 'public' AND t.typname = 'app_role'
    )
    AND to_regproc('public.has_role(uuid,public.app_role)') IS NOT NULL
    AND to_regproc('public.has_role_text(uuid,text)') IS NOT NULL
  THEN 'ok' ELSE 'fail' END;" 2>/dev/null || echo "fail")

if [ "$(echo "$CORE_OK" | tr -d '[:space:]')" != "ok" ]; then
  echo -e "${RED}❌ Dependências core ausentes (app_role/user_roles/has_role).${NC}"
  exit 1
fi
echo -e "   ${GREEN}✅ Dependências core OK${NC}"

echo -e "${BLUE}🪣 Aplicando bootstrap de storage...${NC}"
bash ensure-storage-buckets.sh

echo -e "${BLUE}🔎 Validando buckets mínimos...${NC}"
BUCKETS_OK=$(docker compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" db \
  psql -tA -w -h 127.0.0.1 -U "$DB_ADMIN_USER" -d "$POSTGRES_DB" -c "
  SELECT CASE WHEN (
    SELECT count(*) FROM storage.buckets WHERE id IN (
      'property-media','contract-documents','tenant-documents','inspection-media','sales-documents'
    )
  ) = 5 THEN 'ok' ELSE 'fail' END;" 2>/dev/null || echo "fail")

if [ "$(echo "$BUCKETS_OK" | tr -d '[:space:]')" != "ok" ]; then
  echo -e "${RED}❌ Buckets obrigatórios não foram criados corretamente.${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Bootstrap DB + Storage concluído com sucesso${NC}"
