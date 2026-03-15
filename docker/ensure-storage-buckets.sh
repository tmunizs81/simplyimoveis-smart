#!/bin/bash
# ============================================================
# Garante buckets e policies de storage (pipeline idempotente)
# Uso: bash ensure-storage-buckets.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

[ ! -f .env ] && echo -e "${RED}❌ .env não encontrado${NC}" && exit 1
[ ! -f sql/bootstrap-storage.sql ] && echo -e "${RED}❌ sql/bootstrap-storage.sql não encontrado${NC}" && exit 1

read_env() { grep -E "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"; }

POSTGRES_PASSWORD=$(read_env "POSTGRES_PASSWORD")
POSTGRES_DB=$(read_env "POSTGRES_DB"); POSTGRES_DB="${POSTGRES_DB:-simply_db}"
DB_ADMIN_USER=$(read_env "POSTGRES_USER"); DB_ADMIN_USER="${DB_ADMIN_USER:-supabase_admin}"

[ -z "${POSTGRES_PASSWORD:-}" ] && echo -e "${RED}❌ POSTGRES_PASSWORD vazio${NC}" && exit 1

echo -e "${BLUE}🪣 Aplicando bootstrap de storage...${NC}"

# Dependências explícitas: tabela e função de roles devem existir antes das policies de storage
ROLE_DEPS_OK=$(docker compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" db \
  psql -tA -w -h 127.0.0.1 -U "$DB_ADMIN_USER" -d "$POSTGRES_DB" -c "
  SELECT
    CASE
      WHEN to_regclass('public.user_roles') IS NOT NULL
       AND to_regprocedure('public.has_role_text(uuid,text)') IS NOT NULL
      THEN 'ok' ELSE 'fail' END;" 2>/dev/null || echo "fail")

if [ "$(echo "$ROLE_DEPS_OK" | tr -d '[:space:]')" != "ok" ]; then
  echo -e "${RED}❌ Dependências ausentes para policies de storage.${NC}"
  echo -e "${YELLOW}   Esperado: public.user_roles e public.has_role_text(uuid,text)${NC}"
  exit 1
fi

echo -e "   Arquivo: $(realpath sql/bootstrap-storage.sql)"
docker compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" db \
  psql -v ON_ERROR_STOP=1 -w -h 127.0.0.1 -U "$DB_ADMIN_USER" -d "$POSTGRES_DB" < sql/bootstrap-storage.sql

echo -e "${GREEN}✅ Buckets e policies de storage aplicados${NC}"
