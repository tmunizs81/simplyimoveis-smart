#!/bin/bash
# ============================================================
# Simply Imóveis - Restaurar backup completo (DB + Storage)
# Uso: bash restore.sh /caminho/do/backup.sql.gz
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'

BACKUP_FILE="${1:-}"

if [ -z "$BACKUP_FILE" ]; then
  echo -e "${BLUE}Uso: bash restore.sh /caminho/do/backup.sql.gz${NC}"
  echo ""
  echo "Backups disponíveis:"
  ls -lh /opt/simply-imoveis/backups/simply-backup-*.sql.gz 2>/dev/null || echo "  Nenhum backup encontrado."
  exit 1
fi

[ ! -f "$BACKUP_FILE" ] && echo -e "${RED}❌ Arquivo não encontrado: $BACKUP_FILE${NC}" && exit 1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

[ ! -f .env ] && echo -e "${RED}❌ .env não encontrado${NC}" && exit 1

read_env() { grep -E "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"; }

POSTGRES_DB=$(read_env "POSTGRES_DB"); POSTGRES_DB="${POSTGRES_DB:-simply_db}"
POSTGRES_PASSWORD=$(read_env "POSTGRES_PASSWORD")
DB_USER=$(read_env "POSTGRES_USER"); DB_USER="${DB_USER:-supabase_admin}"

echo -e "${RED}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║     ⚠️  RESTAURAÇÃO DE BACKUP                        ║${NC}"
echo -e "${RED}║     Isso SUBSTITUIRÁ todos os dados atuais!          ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Arquivo: ${BLUE}${BACKUP_FILE}${NC}"
echo -e "Tamanho: $(du -h "$BACKUP_FILE" | cut -f1)"
echo ""
read -p "Tem certeza? (digite SIM para confirmar): " CONFIRM
[ "$CONFIRM" != "SIM" ] && echo -e "${YELLOW}❌ Cancelado.${NC}" && exit 0

# ── 1) Criar backup de segurança antes de restaurar ──
echo -e "\n${BLUE}1️⃣  Criando backup de segurança pré-restauração...${NC}"
PRE_RESTORE_BACKUP="/opt/simply-imoveis/backups/pre-restore-$(date +%Y%m%d-%H%M%S).sql.gz"
mkdir -p /opt/simply-imoveis/backups

docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" simply-db \
  pg_dump -U "$DB_USER" -h 127.0.0.1 -d "$POSTGRES_DB" \
    --no-owner --no-privileges \
    --exclude-schema=auth --exclude-schema=storage \
    --exclude-schema=supabase_functions --exclude-schema=realtime \
    --exclude-schema=vault --exclude-schema=pgsodium \
    --exclude-schema=graphql --exclude-schema=graphql_public \
    --exclude-schema=extensions --exclude-schema=_realtime \
    --exclude-schema=supabase_migrations --exclude-schema=_analytics \
    --exclude-schema=_supavisor \
  | gzip > "$PRE_RESTORE_BACKUP" 2>/dev/null || true

echo -e "   ${GREEN}✅ Backup de segurança: $PRE_RESTORE_BACKUP${NC}"

# ── 2) Parar serviços que usam o banco ──
echo -e "\n${BLUE}2️⃣  Parando serviços dependentes...${NC}"
docker compose stop auth rest storage functions frontend kong 2>/dev/null || true
echo -e "   ${GREEN}✅ Serviços parados${NC}"

# ── 3) Limpar dados do schema public (preservar auth/storage) ──
echo -e "\n${BLUE}3️⃣  Limpando schema public...${NC}"

docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" simply-db \
  psql -U "$DB_USER" -h 127.0.0.1 -d "$POSTGRES_DB" -c "
    -- Drop all tables in public schema
    DO \$\$
    DECLARE
      r RECORD;
    BEGIN
      FOR r IN (
        SELECT tablename FROM pg_tables
        WHERE schemaname = 'public'
        ORDER BY tablename
      ) LOOP
        EXECUTE 'DROP TABLE IF EXISTS public.' || quote_ident(r.tablename) || ' CASCADE';
      END LOOP;
    END
    \$\$;

    -- Drop all custom types in public schema
    DO \$\$
    DECLARE
      r RECORD;
    BEGIN
      FOR r IN (
        SELECT t.typname
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'public'
          AND t.typtype = 'e'
          AND t.typrelid = 0
      ) LOOP
        EXECUTE 'DROP TYPE IF EXISTS public.' || quote_ident(r.typname) || ' CASCADE';
      END LOOP;
    END
    \$\$;

    -- Drop all functions in public schema
    DO \$\$
    DECLARE
      r RECORD;
    BEGIN
      FOR r IN (
        SELECT p.oid::regprocedure AS func_sig
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
      ) LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.func_sig || ' CASCADE';
      END LOOP;
    END
    \$\$;
  " 2>/dev/null

echo -e "   ${GREEN}✅ Schema public limpo${NC}"

# ── 4) Restaurar dump ──
echo -e "\n${BLUE}4️⃣  Restaurando banco de dados...${NC}"

RESTORE_LOG="/tmp/simply-restore-$(date +%s).log"

gunzip -c "$BACKUP_FILE" | docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" simply-db \
  psql -U "$DB_USER" -h 127.0.0.1 -d "$POSTGRES_DB" \
    --single-transaction \
    -v ON_ERROR_STOP=0 \
  > "$RESTORE_LOG" 2>&1

RESTORE_ERRORS=$(grep -ci "ERROR" "$RESTORE_LOG" 2>/dev/null || echo "0")

if [ "$RESTORE_ERRORS" -gt 0 ]; then
  echo -e "   ${YELLOW}⚠️  ${RESTORE_ERRORS} erro(s) durante restauração (pode ser normal para objetos pré-existentes)${NC}"
  echo -e "   Log: $RESTORE_LOG"
else
  echo -e "   ${GREEN}✅ Banco restaurado sem erros${NC}"
  rm -f "$RESTORE_LOG"
fi

# ── 5) Re-executar bootstrap para garantir integridade ──
echo -e "\n${BLUE}5️⃣  Executando bootstrap para garantir integridade...${NC}"

# Sync passwords e grants
if [ -f "$SCRIPT_DIR/sync-db-passwords.sh" ]; then
  bash "$SCRIPT_DIR/sync-db-passwords.sh" 2>/dev/null || echo -e "   ${YELLOW}⚠️  sync-db-passwords com avisos${NC}"
fi

# Re-apply core SQL (idempotente — vai recriar funções, RLS, grants que possam ter sido perdidos)
if [ -f "$SCRIPT_DIR/sql/selfhosted-admin-recovery.sql" ]; then
  docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" simply-db \
    psql -U "$DB_USER" -h 127.0.0.1 -d "$POSTGRES_DB" \
      -v ON_ERROR_STOP=0 \
    < "$SCRIPT_DIR/sql/selfhosted-admin-recovery.sql" > /dev/null 2>&1 || true
  echo -e "   ${GREEN}✅ Core schema re-aplicado${NC}"
fi

# Re-create storage buckets
if [ -f "$SCRIPT_DIR/ensure-storage-buckets.sh" ]; then
  # Storage needs REST running
  docker compose up -d db rest storage 2>/dev/null || true
  sleep 5
  bash "$SCRIPT_DIR/ensure-storage-buckets.sh" 2>/dev/null || echo -e "   ${YELLOW}⚠️  Storage buckets com avisos${NC}"
fi

# ── 6) Restaurar storage files (se existir backup correspondente) ──
STORAGE_FILE=$(echo "$BACKUP_FILE" | sed 's/simply-backup/simply-storage/' | sed 's/.sql.gz/.tar.gz/')
if [ -f "$STORAGE_FILE" ]; then
  echo -e "\n${BLUE}6️⃣  Restaurando arquivos de storage...${NC}"

  VOLUME_NAME=""
  for candidate in "docker_simply_storage" "simply_storage" "simply-imoveis_simply_storage"; do
    if docker volume inspect "$candidate" >/dev/null 2>&1; then
      VOLUME_NAME="$candidate"
      break
    fi
  done

  if [ -n "$VOLUME_NAME" ]; then
    docker run --rm \
      -v "${VOLUME_NAME}":/data \
      -v "$(dirname "$STORAGE_FILE")":/backup \
      alpine sh -c "rm -rf /data/* && tar xzf /backup/$(basename "$STORAGE_FILE") -C /data" 2>/dev/null || true
    echo -e "   ${GREEN}✅ Storage restaurado${NC}"
  else
    echo -e "   ${YELLOW}⚠️  Volume de storage não encontrado${NC}"
  fi
else
  echo -e "\n${YELLOW}ℹ️  Sem backup de storage correspondente (${STORAGE_FILE})${NC}"
fi

# ── 7) Restart completo ──
echo -e "\n${BLUE}7️⃣  Reiniciando todos os serviços...${NC}"
docker compose up -d
sleep 15
echo -e "   ${GREEN}✅ Serviços reiniciados${NC}"

# ── 8) Validação ──
echo -e "\n${BLUE}8️⃣  Validando restauração...${NC}"

ERRORS=0

# Check DB
TABLE_COUNT=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" simply-db \
  psql -tA -U "$DB_USER" -h 127.0.0.1 -d "$POSTGRES_DB" \
  -c "SELECT count(*) FROM pg_tables WHERE schemaname='public';" 2>/dev/null || echo "0")

if [ "${TABLE_COUNT:-0}" -ge 10 ]; then
  echo -e "   ${GREEN}✅ Banco: ${TABLE_COUNT} tabelas no schema public${NC}"
else
  echo -e "   ${RED}❌ Banco: apenas ${TABLE_COUNT} tabelas (esperado ≥10)${NC}"
  ERRORS=$((ERRORS + 1))
fi

# Check services
for svc in simply-db simply-auth simply-rest simply-kong simply-functions simply-frontend; do
  STATUS=$(docker inspect --format='{{.State.Status}}' "$svc" 2>/dev/null || echo "missing")
  if [ "$STATUS" = "running" ]; then
    echo -e "   ${GREEN}✅ ${svc}: running${NC}"
  else
    echo -e "   ${RED}❌ ${svc}: ${STATUS}${NC}"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""
if [ "$ERRORS" -eq 0 ]; then
  echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║  ✅ Restauração concluída com sucesso!                ║${NC}"
  echo -e "${GREEN}╠══════════════════════════════════════════════════════╣${NC}"
  echo -e "${GREEN}║  Backup de segurança: ${PRE_RESTORE_BACKUP}${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
else
  echo -e "${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${YELLOW}║  ⚠️  Restauração com ${ERRORS} alerta(s)                  ║${NC}"
  echo -e "${YELLOW}║  Backup de segurança: ${PRE_RESTORE_BACKUP}${NC}"
  echo -e "${YELLOW}║  Tente: docker compose restart                      ║${NC}"
  echo -e "${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
fi
