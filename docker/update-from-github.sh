#!/bin/bash
# ============================================================
# Simply Imóveis - Atualizar VPS a partir do GitHub
# Uso: sudo bash update-from-github.sh [repo-url]
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'
INSTALL_DIR="/opt/simply-imoveis"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Simply Imóveis — Atualização via GitHub          ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"

# ── 1. Instalar git se necessário ──
command -v git &>/dev/null || { echo -e "${BLUE}📦 Instalando git...${NC}"; apt-get update -qq >/dev/null 2>&1; apt-get install -y -qq git >/dev/null 2>&1; }

# ── 2. Backup do .env ──
ENV_BACKUP="/tmp/simply-env-backup-$(date +%s)"
[ -f "$INSTALL_DIR/docker/.env" ] && cp "$INSTALL_DIR/docker/.env" "$ENV_BACKUP" && echo -e "   ${GREEN}✅ .env backup: $ENV_BACKUP${NC}"

# ── 3. Pull do código ──
echo -e "\n${BLUE}1️⃣  Atualizando código...${NC}"
if [ -d "$INSTALL_DIR/.git" ]; then
  cd "$INSTALL_DIR"
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
  echo -e "   Branch: $BRANCH"
  git fetch --all --prune
  git reset --hard "origin/$BRANCH"
  echo -e "   ${GREEN}✅ Código atualizado (branch: $BRANCH)${NC}"
else
  REPO_URL="${1:-}"
  [ -z "$REPO_URL" ] && read -p "URL do repositório GitHub: " REPO_URL
  [ -z "$REPO_URL" ] && echo -e "${RED}❌ URL não informada${NC}" && exit 1
  rm -rf "$INSTALL_DIR"
  git clone "$REPO_URL" "$INSTALL_DIR"
  echo -e "   ${GREEN}✅ Repositório clonado${NC}"
fi

# ── 4. Restaurar .env ──
[ -f "$ENV_BACKUP" ] && cp "$ENV_BACKUP" "$INSTALL_DIR/docker/.env" && echo -e "   ${GREEN}✅ .env restaurado${NC}"

# ── 5. Permissões ──
cd "$INSTALL_DIR/docker"
chmod +x *.sh 2>/dev/null || true
chmod +x volumes/db/init/*.sh 2>/dev/null || true

# ── 6. Validar arquivos essenciais ──
echo -e "\n${BLUE}2️⃣  Validando estrutura...${NC}"
MISSING=0
for f in .env docker-compose.yml sql/selfhosted-admin-recovery.sql sql/bootstrap-storage.sql sync-functions.sh render-kong-config.sh bootstrap-db.sh ensure-storage-buckets.sh sync-db-passwords.sh validate-install.sh; do
  if [ ! -f "$f" ]; then
    echo -e "   ${RED}❌ Ausente: $f${NC}"
    MISSING=$((MISSING + 1))
  fi
done
[ "$MISSING" -gt 0 ] && echo -e "${RED}❌ $MISSING arquivo(s) ausente(s). Abortando.${NC}" && exit 1
echo -e "   ${GREEN}✅ Todos os arquivos presentes${NC}"

read_env() { grep -E "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"; }
POSTGRES_PASSWORD=$(read_env "POSTGRES_PASSWORD")
POSTGRES_DB=$(read_env "POSTGRES_DB"); POSTGRES_DB="${POSTGRES_DB:-simply_db}"
DB_USER=$(read_env "POSTGRES_USER"); DB_USER="${DB_USER:-supabase_admin}"

# ── 7. Sync functions + Kong ──
echo -e "\n${BLUE}3️⃣  Sincronizando Edge Functions e Kong...${NC}"
bash sync-functions.sh "$INSTALL_DIR/supabase/functions" "volumes/functions"
bash render-kong-config.sh
echo -e "   ${GREEN}✅ Functions e Kong sincronizados${NC}"

# ── 8. Rebuild e restart ──
echo -e "\n${BLUE}4️⃣  Rebuild frontend + restart serviços...${NC}"
docker compose build --no-cache frontend
docker compose up -d --force-recreate frontend functions kong
echo -e "   ${GREEN}✅ Frontend, Functions e Kong reiniciados${NC}"

# ── 9. Aplicar migrations (bootstrap completo) ──
echo -e "\n${BLUE}5️⃣  Aplicando bootstrap DB + Storage...${NC}"
bash sync-db-passwords.sh || echo -e "${YELLOW}⚠️  sync-db-passwords com alertas${NC}"

# Aplicar recovery SQL via stdin (não via -f que busca dentro do container)
docker compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" db \
  psql -v ON_ERROR_STOP=1 -w -h 127.0.0.1 -U "$DB_USER" -d "$POSTGRES_DB" < sql/selfhosted-admin-recovery.sql || \
  echo -e "${YELLOW}⚠️  Recovery SQL com alertas${NC}"

bash ensure-storage-buckets.sh || echo -e "${YELLOW}⚠️  ensure-storage-buckets com alertas${NC}"

# ── 10. Restart final ──
echo -e "\n${BLUE}6️⃣  Restart final dos serviços...${NC}"
docker compose up -d --force-recreate auth rest storage
sleep 15

# ── 11. Validação ──
echo -e "\n${BLUE}7️⃣  Validando instalação...${NC}"
if ! bash validate-install.sh; then
  echo -e "${YELLOW}⚠️  Primeira validação falhou. Reiniciando serviços...${NC}"
  docker compose restart auth rest storage kong functions
  sleep 20
  bash validate-install.sh || echo -e "${YELLOW}⚠️  Validação ainda com alertas — verifique: docker compose logs --tail=50${NC}"
fi

echo -e "\n${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     ✅ Atualização concluída com sucesso!             ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Próximos passos:"
echo -e "  • Acesse o site e teste o /admin"
echo -e "  • Se precisar recriar admin: ${BLUE}bash create-admin.sh email senha${NC}"
echo ""
