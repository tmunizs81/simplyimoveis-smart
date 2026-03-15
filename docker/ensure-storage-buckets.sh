#!/bin/bash
# ============================================================
# Garante buckets e policies de storage (pipeline idempotente)
# SQL enviado via STDIN (arquivo no HOST, não no container)
# Uso: bash ensure-storage-buckets.sh
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

SQL_FILE="$SCRIPT_DIR/sql/bootstrap-storage.sql"

[ ! -f "$SCRIPT_DIR/.env" ] && echo -e "${RED}❌ .env não encontrado em $SCRIPT_DIR${NC}" && exit 1
[ ! -f "$SQL_FILE" ] && echo -e "${RED}❌ SQL não encontrado: $SQL_FILE${NC}" && exit 1

read_env() { grep -E "^${1}=" "$SCRIPT_DIR/.env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"; }

POSTGRES_PASSWORD=$(read_env "POSTGRES_PASSWORD")
POSTGRES_DB=$(read_env "POSTGRES_DB"); POSTGRES_DB="${POSTGRES_DB:-simply_db}"
DB_ADMIN_USER=$(read_env "POSTGRES_USER"); DB_ADMIN_USER="${DB_ADMIN_USER:-supabase_admin}"

[ -z "${POSTGRES_PASSWORD:-}" ] && echo -e "${RED}❌ POSTGRES_PASSWORD vazio${NC}" && exit 1

# Validar dependências
echo -e "${BLUE}🔎 Validando dependências para storage...${NC}"
ROLE_DEPS_OK=$(docker compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" db \
  psql -tA -w -h 127.0.0.1 -U "$DB_ADMIN_USER" -d "$POSTGRES_DB" -c "
  SELECT CASE WHEN
    to_regclass('public.user_roles') IS NOT NULL
    AND to_regtype('public.app_role') IS NOT NULL
    AND to_regprocedure('public.has_role(uuid,public.app_role)') IS NOT NULL
  THEN 'ok' ELSE 'fail' END;" 2>/dev/null || echo "fail")

if [ "$(echo "$ROLE_DEPS_OK" | tr -d '[:space:]')" != "ok" ]; then
  echo -e "${RED}❌ Dependências ausentes: user_roles/app_role/has_role(uuid,app_role)${NC}"
  echo -e "${YELLOW}   Dependência é criada por sql/selfhosted-admin-recovery.sql via bootstrap-db.sh.${NC}"
  exit 1
fi

echo -e "${BLUE}🪣 Aplicando storage SQL...${NC}"
docker compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" db \
  psql -v ON_ERROR_STOP=1 -w -h 127.0.0.1 -U "$DB_ADMIN_USER" -d "$POSTGRES_DB" \
  < "$SQL_FILE"

echo -e "${GREEN}✅ Buckets e policies de storage aplicados${NC}"
