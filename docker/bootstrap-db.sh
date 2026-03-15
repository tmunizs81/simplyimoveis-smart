#!/bin/bash
# ============================================================
# Simply Imóveis - Bootstrap completo do banco (pipeline)
# Ordem: passwords → core SQL (types/tables/functions/RLS) →
#        validate core → start storage service → storage SQL
# 
# IMPORTANTE: Todos os SQL são enviados via STDIN (< arquivo)
# porque os arquivos existem no HOST, não dentro do container.
# Uso: bash bootstrap-db.sh
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Validar arquivos necessários ──
echo -e "${BLUE}🔎 Validando arquivos do bootstrap...${NC}"
MISSING=0
for f in .env sql/selfhosted-admin-recovery.sql sql/bootstrap-storage.sql sync-db-passwords.sh ensure-storage-buckets.sh; do
  if [ ! -f "$SCRIPT_DIR/$f" ]; then
    echo -e "${RED}❌ Arquivo ausente: $SCRIPT_DIR/$f${NC}"
    MISSING=$((MISSING + 1))
  fi
done
[ "$MISSING" -gt 0 ] && exit 1
echo -e "   ${GREEN}✅ Todos os arquivos presentes${NC}"

# ── Ler configuração ──
read_env() { grep -E "^${1}=" "$SCRIPT_DIR/.env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"; }

POSTGRES_PASSWORD=$(read_env "POSTGRES_PASSWORD")
POSTGRES_DB=$(read_env "POSTGRES_DB"); POSTGRES_DB="${POSTGRES_DB:-simply_db}"
DB_ADMIN_USER=$(read_env "POSTGRES_USER"); DB_ADMIN_USER="${DB_ADMIN_USER:-supabase_admin}"

[ -z "${POSTGRES_PASSWORD:-}" ] && echo -e "${RED}❌ POSTGRES_PASSWORD vazio${NC}" && exit 1

# ── ETAPA 1: Aguardar PostgreSQL ──
echo -e "${BLUE}⏳ Aguardando PostgreSQL...${NC}"
for i in {1..60}; do
  if docker exec simply-db pg_isready -U "$DB_ADMIN_USER" -d "$POSTGRES_DB" -q 2>/dev/null; then
    break
  fi
  [ "$i" = "60" ] && echo -e "${RED}❌ PostgreSQL não respondeu em 120s${NC}" && exit 1
  sleep 2
done
echo -e "   ${GREEN}✅ PostgreSQL pronto${NC}"

# ── ETAPA 2: Sincronizar senhas/roles/grants ──
echo -e "${BLUE}🔐 Sincronizando roles e credenciais...${NC}"
bash "$SCRIPT_DIR/sync-db-passwords.sh"

# ── ETAPA 3: Aplicar core SQL (types → tables → functions → RLS → grants) ──
echo -e "${BLUE}🧱 Aplicando core SQL (schema/types/functions/RLS)...${NC}"
docker compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" db \
  psql -v ON_ERROR_STOP=1 -w -h 127.0.0.1 -U "$DB_ADMIN_USER" -d "$POSTGRES_DB" \
  < "$SCRIPT_DIR/sql/selfhosted-admin-recovery.sql"
echo -e "   ${GREEN}✅ Core SQL aplicado${NC}"

# ── ETAPA 4: Validar dependências core ──
echo -e "${BLUE}🔎 Validando dependências core...${NC}"
CORE_OK=$(docker compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" db \
  psql -tA -w -h 127.0.0.1 -U "$DB_ADMIN_USER" -d "$POSTGRES_DB" -c "
  SELECT CASE WHEN
    to_regclass('public.user_roles') IS NOT NULL
    AND EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'public' AND t.typname = 'app_role')
    AND to_regprocedure('public.has_role(uuid,public.app_role)') IS NOT NULL
    AND to_regprocedure('public.has_role_text(uuid,text)') IS NOT NULL
  THEN 'ok' ELSE 'fail' END;" 2>/dev/null || echo "fail")

if [ "$(echo "$CORE_OK" | tr -d '[:space:]')" != "ok" ]; then
  echo -e "${RED}❌ Dependências core ausentes após aplicar SQL.${NC}"
  echo -e "${RED}   Esperado: app_role enum, user_roles table, has_role(), has_role_text()${NC}"
  exit 1
fi
echo -e "   ${GREEN}✅ Dependências core validadas${NC}"

# ── ETAPA 5: Subir storage + rest para migrations do storage schema ──
echo -e "${BLUE}🧩 Subindo rest + storage...${NC}"
docker compose up -d rest storage

echo -e "${BLUE}⏳ Aguardando storage schema...${NC}"
for i in {1..60}; do
  STORAGE_READY=$(docker compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" db \
    psql -tA -w -h 127.0.0.1 -U "$DB_ADMIN_USER" -d "$POSTGRES_DB" -c "
    SELECT CASE WHEN to_regclass('storage.buckets') IS NOT NULL AND to_regclass('storage.objects') IS NOT NULL THEN 'ok' ELSE 'wait' END;" 2>/dev/null || echo "wait")
  [ "$(echo "$STORAGE_READY" | tr -d '[:space:]')" = "ok" ] && break
  [ "$i" = "60" ] && echo -e "${RED}❌ storage.buckets/objects não disponíveis após 120s${NC}" && exit 1
  sleep 2
done
echo -e "   ${GREEN}✅ Storage schema disponível${NC}"

# ── ETAPA 6: Aplicar storage SQL (buckets + policies) ──
echo -e "${BLUE}🪣 Aplicando storage SQL (buckets + policies)...${NC}"
bash "$SCRIPT_DIR/ensure-storage-buckets.sh"

# ── ETAPA 7: Validar buckets ──
echo -e "${BLUE}🔎 Validando buckets...${NC}"
BUCKETS_OK=$(docker compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" db \
  psql -tA -w -h 127.0.0.1 -U "$DB_ADMIN_USER" -d "$POSTGRES_DB" -c "
  SELECT CASE WHEN (
    SELECT count(*) FROM storage.buckets WHERE id IN (
      'property-media','contract-documents','tenant-documents','inspection-media','sales-documents'
    )
  ) = 5 THEN 'ok' ELSE 'fail' END;" 2>/dev/null || echo "fail")

if [ "$(echo "$BUCKETS_OK" | tr -d '[:space:]')" != "ok" ]; then
  echo -e "${RED}❌ Buckets obrigatórios não foram criados.${NC}"
  exit 1
fi
echo -e "   ${GREEN}✅ Buckets validados${NC}"

echo -e "\n${GREEN}✅ Bootstrap DB + Storage concluído com sucesso!${NC}"
