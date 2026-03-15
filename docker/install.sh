#!/bin/bash
# ============================================================
# Simply Imóveis - Instalador Docker Simplificado
# Versão: 2026-03-15-v11-simplified
# Uso: sudo bash install.sh [--clean]
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║     Simply Imóveis - Instalador v11 (simplified)     ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

[ "$EUID" -ne 0 ] && echo -e "${RED}❌ Execute com sudo${NC}" && exit 1

FORCE_CLEAN=false
[[ "${1:-}" == "--clean" ]] && FORCE_CLEAN=true

ADMIN_EMAIL=""
ADMIN_PASS=""

# ── Helpers ──
read_env() { grep -E "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"; }
set_env() {
  local k="$1" v="$2"
  if grep -qE "^${k}=" .env 2>/dev/null; then
    sed -i "s|^${k}=.*|${k}=\"${v}\"|" .env
  else
    echo "${k}=\"${v}\"" >> .env
  fi
}
prompt_config() {
  local var="$1" desc="$2" default="${3:-}" secret="${4:-false}"
  local cur; cur=$(read_env "$var")
  [ -n "$cur" ] && [ "$cur" != "CHANGE_ME" ] && [ "$cur" != "gsk_XXXXXXXXXXXXXXXXXXXX" ] \
    && [ "$cur" != "seu-email@gmail.com" ] && [ "$cur" != "sua-senha-de-app" ] && return 0
  echo -e "\n${CYAN}📝 ${desc}${NC}"
  [ -n "$default" ] && echo -e "   Padrão: ${default}"
  if [ "$secret" = "true" ]; then read -s -p "   > " val; echo ""; else read -p "   > " val; fi
  val="${val:-$default}"
  [ -n "$val" ] && set_env "$var" "$val"
}

wait_healthy() {
  local container="$1" timeout="${2:-120}"
  for i in $(seq 1 $((timeout/2))); do
    local st=$(docker inspect -f '{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
    [ "$st" = "healthy" ] && return 0
    # Fallback: check running
    [ "$st" = "none" ] && docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null | grep -q running && return 0
    sleep 2
  done
  echo -e "${RED}❌ $container não ficou saudável em ${timeout}s${NC}"
  docker logs --tail=20 "$container" 2>/dev/null || true
  return 1
}

# ── 1. Dependências ──
echo -e "${BLUE}📦 Instalando dependências...${NC}"
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq rsync curl openssl jq nginx certbot python3-certbot-nginx >/dev/null 2>&1
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker && systemctl start docker
fi
docker compose version &>/dev/null || apt-get install -y -qq docker-compose-plugin >/dev/null 2>&1

# ── 2. Copiar projeto ──
INSTALL_DIR="/opt/simply-imoveis"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

mkdir -p "$INSTALL_DIR"
echo -e "${BLUE}📋 Copiando projeto...${NC}"
rsync -av --delete --exclude='node_modules' --exclude='.git' --exclude='docker/.env' "$PROJECT_DIR/" "$INSTALL_DIR/"
cd "$INSTALL_DIR/docker"
chmod +x *.sh 2>/dev/null || true
chmod +x volumes/db/init/*.sh 2>/dev/null || true

# ── 3. Criar/verificar .env ──
[ ! -f .env ] && cp .env.example .env

# ── 4. Gerar credenciais automáticas ──
echo -e "${BLUE}🔑 Gerando credenciais...${NC}"

CURRENT_JWT=$(read_env "JWT_SECRET")
if [ -z "$CURRENT_JWT" ] || [ "$CURRENT_JWT" = "super-secret-jwt-token-with-at-least-32-characters-long" ]; then
  set_env "JWT_SECRET" "$(openssl rand -base64 32)"
  echo -e "   ${GREEN}✅ JWT_SECRET${NC}"
fi

CURRENT_PG=$(read_env "POSTGRES_PASSWORD")
if [ -z "$CURRENT_PG" ] || [ "$CURRENT_PG" = "SuaSenhaForteAqui123!" ]; then
  set_env "POSTGRES_PASSWORD" "$(openssl rand -base64 24 | tr -d '=/+')"
  echo -e "   ${GREEN}✅ POSTGRES_PASSWORD${NC}"
fi

[ -z "$(read_env "POSTGRES_USER")" ] && set_env "POSTGRES_USER" "supabase_admin"

CURRENT_ANON=$(read_env "ANON_KEY")
if [ -z "$CURRENT_ANON" ] || [ "$CURRENT_ANON" = "CHANGE_ME" ]; then
  JWT_SECRET=$(read_env "JWT_SECRET")
  gen_jwt() {
    local js="const c=require('crypto');const h=Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url');const p=Buffer.from(JSON.stringify({ref:'simply',role:'$1',iss:'supabase',iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+315360000})).toString('base64url');const s=c.createHmac('sha256','${JWT_SECRET}').update(h+'.'+p).digest('base64url');console.log(h+'.'+p+'.'+s);"
    command -v node &>/dev/null && node -e "$js" || docker run --rm node:20-alpine node -e "$js"
  }
  ANON=$(gen_jwt "anon"); SERVICE=$(gen_jwt "service_role")
  [ -z "$ANON" ] || [ -z "$SERVICE" ] && echo -e "${RED}❌ Falha JWT${NC}" && exit 1
  set_env "ANON_KEY" "$ANON"; set_env "SERVICE_ROLE_KEY" "$SERVICE"
  echo -e "   ${GREEN}✅ ANON_KEY + SERVICE_ROLE_KEY${NC}"
fi

# ── 5. Configuração interativa ──
echo -e "\n${BLUE}════ Configuração ════${NC}"
prompt_config "SITE_DOMAIN" "Domínio do site" "simplyimoveis.com.br"
prompt_config "SMTP_HOST" "Servidor SMTP" "smtp.gmail.com"
prompt_config "SMTP_PORT" "Porta SMTP" "587"
prompt_config "SMTP_USER" "Email SMTP"
prompt_config "SMTP_PASS" "Senha SMTP" "" "true"
prompt_config "SMTP_SENDER_NAME" "Nome remetente" "Simply Imóveis"
prompt_config "SMTP_ADMIN_EMAIL" "Email admin" "admin@simplyimoveis.com.br"
prompt_config "GROQ_API_KEY" "Chave Groq (chat IA)" "" "true"
prompt_config "TELEGRAM_BOT_TOKEN" "Telegram Bot Token (ENTER p/ pular)" ""
prompt_config "TELEGRAM_CHAT_ID" "Telegram Chat ID" ""

# Admin credentials
default_admin="$(read_env "SMTP_ADMIN_EMAIL")"
default_admin="${default_admin:-admin@simplyimoveis.com.br}"
read -p "🧑‍💼 Email admin [$default_admin]: " ADMIN_EMAIL
ADMIN_EMAIL="${ADMIN_EMAIL:-$default_admin}"
while [[ ! "$ADMIN_EMAIL" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; do
  read -p "   Email inválido. Tente: " ADMIN_EMAIL
done
while true; do
  read -s -p "🔐 Senha admin (mín 8 chars): " ADMIN_PASS; echo ""
  [ ${#ADMIN_PASS} -ge 8 ] && break
  echo -e "${YELLOW}⚠️  Muito curta${NC}"
done

# ── 6. Preparar Kong + Edge Functions ──
echo -e "${BLUE}🔧 Preparando configurações...${NC}"
bash render-kong-config.sh
bash sync-functions.sh "$INSTALL_DIR/supabase/functions" "volumes/functions"

# ── 7. Limpar se necessário ──
EXISTING=$(docker compose ps -q 2>/dev/null | wc -l)
if [ "$EXISTING" -gt 0 ]; then
  if [ "$FORCE_CLEAN" = "true" ]; then
    echo -e "${BLUE}🧹 Limpando instalação anterior...${NC}"
    docker compose down -v --remove-orphans 2>/dev/null || true
  else
    read -p "Instalação anterior detectada. Limpar? (S/n): " CLEAN
    [[ ! "$CLEAN" =~ ^[nN]$ ]] && docker compose down -v --remove-orphans 2>/dev/null || true
  fi
fi

# ── 8. Subir banco e aguardar ──
echo -e "\n${BLUE}🐘 Subindo banco de dados...${NC}"
docker compose up -d --build db

echo -e "${BLUE}⏳ Aguardando banco...${NC}"
DB_USER=$(read_env "POSTGRES_USER"); DB_USER="${DB_USER:-supabase_admin}"
DB_NAME=$(read_env "POSTGRES_DB"); DB_NAME="${DB_NAME:-simply_db}"
for i in {1..60}; do
  docker exec simply-db pg_isready -U "$DB_USER" -d "$DB_NAME" -q 2>/dev/null && break
  [ "$i" = "60" ] && echo -e "${RED}❌ Banco não respondeu${NC}" && exit 1
  sleep 2
done
echo -e "   ${GREEN}✅ Banco OK${NC}"

# Aguardar init scripts
echo -e "${BLUE}⏳ Aguardando init scripts (10s)...${NC}"
sleep 10

# ── 9. Sync passwords (garante roles mesmo se init falhou parcialmente) ──
echo -e "${BLUE}🔐 Sincronizando credenciais...${NC}"
bash sync-db-passwords.sh || { echo -e "${RED}❌ Falha nas credenciais${NC}"; exit 1; }

# ── 10. Subir tudo ──
echo -e "\n${BLUE}🚀 Subindo todos os serviços...${NC}"
docker compose up -d --build --remove-orphans

echo -e "${BLUE}⏳ Aguardando serviços (20s)...${NC}"
sleep 20

# ── 11. Buckets ──
echo -e "${BLUE}🪣 Verificando buckets...${NC}"
bash ensure-storage-buckets.sh || echo -e "${YELLOW}⚠️  Buckets serão criados no próximo restart${NC}"

# ── 12. Validação ──
echo -e "${BLUE}🧪 Validando...${NC}"
if ! bash validate-install.sh; then
  echo -e "${YELLOW}⚠️  Reiniciando serviços...${NC}"
  docker compose restart auth rest storage kong functions
  sleep 15
  bash validate-install.sh || { echo -e "${RED}❌ Validação falhou. Debug: docker compose logs --tail=50${NC}"; exit 1; }
fi

# ── 13. Criar admin ──
echo -e "${BLUE}👤 Criando admin...${NC}"
bash create-admin.sh "$ADMIN_EMAIL" "$ADMIN_PASS"

# ── 14. SSL ──
SITE_DOMAIN=$(read_env "SITE_DOMAIN")
FRONTEND_PORT=$(read_env "FRONTEND_PORT"); FRONTEND_PORT="${FRONTEND_PORT:-3000}"
KONG_PORT=$(read_env "KONG_HTTP_PORT"); KONG_PORT="${KONG_PORT:-8000}"

read -p "Configurar SSL (Nginx + Let's Encrypt)? (s/N): " DO_SSL
if [[ "$DO_SSL" =~ ^[sS]$ ]]; then
  bash setup-ssl.sh
fi

# ── Resultado ──
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        ✅ Instalação concluída!                      ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  Frontend: http://localhost:${FRONTEND_PORT}                     ║${NC}"
echo -e "${GREEN}║  API:      http://localhost:${KONG_PORT}                     ║${NC}"
echo -e "${GREEN}║  Admin:    https://${SITE_DOMAIN}/admin              ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  Login: ${ADMIN_EMAIL}                              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo -e "\n${YELLOW}⚠️  Altere a senha do admin no primeiro acesso!${NC}"
