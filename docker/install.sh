#!/bin/bash
# ============================================================
# Simply Imóveis - Instalador Definitivo para Ubuntu 24.04 LTS
# Versão: 2026-03-15-v12-production
# Uso: sudo bash install.sh [--clean] [--skip-ssl]
#
# Flags:
#   --clean     Full wipe antes de instalar
#   --skip-ssl  Pular configuração SSL
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║     Simply Imóveis - Instalador v12 (production)     ║"
echo "║     Ubuntu 24.04 LTS + Docker                        ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

[ "$EUID" -ne 0 ] && echo -e "${RED}❌ Execute com sudo: sudo bash install.sh${NC}" && exit 1

# ── Parse flags ──
FORCE_CLEAN=false
SKIP_SSL=false
for arg in "$@"; do
  case "$arg" in
    --clean) FORCE_CLEAN=true ;;
    --skip-ssl) SKIP_SSL=true ;;
  esac
done

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
  local var="$1" desc="$2" default="${3:-}" secret="${4:-false}" required="${5:-false}"
  local cur; cur=$(read_env "$var")
  [ -n "$cur" ] && [ "$cur" != "CHANGE_ME" ] && [ "$cur" != "gsk_XXXXXXXXXXXXXXXXXXXX" ] \
    && [ "$cur" != "seu-email@gmail.com" ] && [ "$cur" != "sua-senha-de-app" ] && return 0

  echo -e "\n${CYAN}📝 ${desc}${NC}"
  [ -n "$default" ] && echo -e "   Padrão: ${default}"
  if [ "$required" = "true" ]; then echo -e "   ${YELLOW}(obrigatório)${NC}"; fi
  if [ "$secret" = "true" ]; then read -s -p "   > " val; echo ""; else read -p "   > " val; fi
  val="${val:-$default}"

  if [ "$required" = "true" ] && [ -z "$val" ]; then
    echo -e "${RED}❌ Valor obrigatório. Abortando.${NC}"
    exit 1
  fi

  [ -n "$val" ] && set_env "$var" "$val"
}

wait_healthy() {
  local container="$1" timeout="${2:-120}"
  for i in $(seq 1 $((timeout/2))); do
    local st=$(docker inspect -f '{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
    [ "$st" = "healthy" ] && return 0
    [ "$st" = "none" ] && docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null | grep -q running && return 0
    sleep 2
  done
  echo -e "${RED}❌ $container não ficou saudável em ${timeout}s${NC}"
  docker logs --tail=20 "$container" 2>/dev/null || true
  return 1
}

# ════════════════════════════════════════════════════════════
# ETAPA 1 — Verificações do host
# ════════════════════════════════════════════════════════════
echo -e "${BLUE}🔍 Verificando sistema...${NC}"

# Verificar Ubuntu
if [ -f /etc/os-release ]; then
  . /etc/os-release
  echo -e "   OS: $PRETTY_NAME"
fi

# Verificar portas em uso
for port in 5432 3000 8000; do
  if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
    PROC=$(ss -tlnp 2>/dev/null | grep ":${port} " | head -1)
    echo -e "${YELLOW}⚠️  Porta $port em uso: $PROC${NC}"
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "simply-"; then
      echo -e "${RED}❌ Porta $port em uso por processo externo. Libere antes de instalar.${NC}"
      exit 1
    fi
  fi
done

# ════════════════════════════════════════════════════════════
# ETAPA 2 — Full Wipe (se --clean ou instalação anterior)
# ════════════════════════════════════════════════════════════
EXISTING=$(docker ps -a --filter "name=simply-" -q 2>/dev/null | wc -l || echo "0")
if [ "$FORCE_CLEAN" = "true" ]; then
  echo -e "${BLUE}🧹 Full wipe solicitado...${NC}"
  bash "$(dirname "$0")/full-wipe.sh" --force 2>/dev/null || true
elif [ "$EXISTING" -gt 0 ]; then
  echo -e "${YELLOW}⚠️  Instalação anterior detectada ($EXISTING containers).${NC}"
  read -p "Limpar tudo e reinstalar do zero? (S/n): " DO_CLEAN
  if [[ ! "$DO_CLEAN" =~ ^[nN]$ ]]; then
    bash "$(dirname "$0")/full-wipe.sh" --force 2>/dev/null || true
  fi
fi

# ════════════════════════════════════════════════════════════
# ETAPA 3 — Instalação de Docker e dependências
# ════════════════════════════════════════════════════════════
echo -e "\n${BLUE}📦 Instalando dependências do sistema...${NC}"
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq rsync curl openssl jq nginx certbot python3-certbot-nginx ca-certificates gnupg lsb-release >/dev/null 2>&1

if ! command -v docker &>/dev/null; then
  echo -e "${BLUE}🐳 Instalando Docker Engine...${NC}"
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker && systemctl start docker
  echo -e "   ${GREEN}✅ Docker instalado${NC}"
else
  echo -e "   ${GREEN}✅ Docker já instalado: $(docker --version)${NC}"
fi

docker compose version &>/dev/null || apt-get install -y -qq docker-compose-plugin >/dev/null 2>&1

# Verificar Docker funciona
docker info >/dev/null 2>&1 || { echo -e "${RED}❌ Docker não funciona${NC}"; exit 1; }
echo -e "   ${GREEN}✅ Docker Compose: $(docker compose version --short)${NC}"

# ════════════════════════════════════════════════════════════
# ETAPA 4 — Copiar projeto para /opt/simply-imoveis
# ════════════════════════════════════════════════════════════
INSTALL_DIR="/opt/simply-imoveis"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

mkdir -p "$INSTALL_DIR"
echo -e "${BLUE}📋 Copiando projeto para $INSTALL_DIR...${NC}"
rsync -av --delete \
  --exclude='node_modules' \
  --exclude='.git' \
  --exclude='docker/.env' \
  "$PROJECT_DIR/" "$INSTALL_DIR/"

cd "$INSTALL_DIR/docker"
chmod +x *.sh 2>/dev/null || true
chmod +x volumes/db/init/*.sh 2>/dev/null || true
mkdir -p sql

echo -e "   ${GREEN}✅ Projeto copiado${NC}"

# ════════════════════════════════════════════════════════════
# ETAPA 5 — Configuração do .env
# ════════════════════════════════════════════════════════════
echo -e "\n${BLUE}════ Configuração de Variáveis ════${NC}"

[ ! -f .env ] && cp .env.example .env

# Gerar credenciais automáticas
echo -e "${BLUE}🔑 Gerando credenciais automáticas...${NC}"

CURRENT_JWT=$(read_env "JWT_SECRET")
if [ -z "$CURRENT_JWT" ] || [ "$CURRENT_JWT" = "super-secret-jwt-token-with-at-least-32-characters-long" ]; then
  set_env "JWT_SECRET" "$(openssl rand -base64 32)"
  echo -e "   ${GREEN}✅ JWT_SECRET gerado${NC}"
fi

CURRENT_PG=$(read_env "POSTGRES_PASSWORD")
if [ -z "$CURRENT_PG" ] || [ "$CURRENT_PG" = "SuaSenhaForteAqui123!" ]; then
  set_env "POSTGRES_PASSWORD" "$(openssl rand -base64 24 | tr -d '=/+')"
  echo -e "   ${GREEN}✅ POSTGRES_PASSWORD gerado${NC}"
fi

[ -z "$(read_env "POSTGRES_USER")" ] && set_env "POSTGRES_USER" "supabase_admin"

# JWT Keys
CURRENT_ANON=$(read_env "ANON_KEY")
if [ -z "$CURRENT_ANON" ] || [ "$CURRENT_ANON" = "CHANGE_ME" ]; then
  JWT_SECRET=$(read_env "JWT_SECRET")
  gen_jwt() {
    local js="const c=require('crypto');const h=Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url');const p=Buffer.from(JSON.stringify({ref:'simply',role:'$1',iss:'supabase',iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+315360000})).toString('base64url');const s=c.createHmac('sha256','${JWT_SECRET}').update(h+'.'+p).digest('base64url');console.log(h+'.'+p+'.'+s);"
    command -v node &>/dev/null && node -e "$js" || docker run --rm node:20-alpine node -e "$js"
  }
  ANON=$(gen_jwt "anon"); SERVICE=$(gen_jwt "service_role")
  [ -z "$ANON" ] || [ -z "$SERVICE" ] && echo -e "${RED}❌ Falha ao gerar JWT${NC}" && exit 1
  set_env "ANON_KEY" "$ANON"
  set_env "SERVICE_ROLE_KEY" "$SERVICE"
  echo -e "   ${GREEN}✅ ANON_KEY + SERVICE_ROLE_KEY gerados${NC}"
fi

# Configuração interativa
echo -e "\n${CYAN}═══ Configurações do Site ═══${NC}"
prompt_config "SITE_DOMAIN" "Domínio do site (ex: simplyimoveis.com.br)" "simplyimoveis.com.br" "false" "true"

echo -e "\n${CYAN}═══ SMTP (email de confirmação) ═══${NC}"
prompt_config "SMTP_HOST" "Servidor SMTP" "smtp.gmail.com"
prompt_config "SMTP_PORT" "Porta SMTP" "587"
prompt_config "SMTP_USER" "Email SMTP"
prompt_config "SMTP_PASS" "Senha SMTP (App Password do Gmail)" "" "true"
prompt_config "SMTP_SENDER_NAME" "Nome do remetente" "Simply Imóveis"
prompt_config "SMTP_ADMIN_EMAIL" "Email do admin" "admin@simplyimoveis.com.br"

echo -e "\n${CYAN}═══ Integrações ═══${NC}"
prompt_config "GROQ_API_KEY" "Chave Groq API (chat IA - https://console.groq.com)" "" "true"

echo -e "\n${CYAN}═══ Telegram (opcional - ENTER para pular) ═══${NC}"
echo -e "   ${YELLOW}Para criar um bot: https://t.me/BotFather${NC}"
echo -e "   ${YELLOW}Para obter chat_id: envie msg ao bot e acesse https://api.telegram.org/bot<TOKEN>/getUpdates${NC}"
prompt_config "TELEGRAM_BOT_TOKEN" "Telegram Bot Token"
prompt_config "TELEGRAM_CHAT_ID" "Telegram Chat ID"

# Admin credentials
echo -e "\n${CYAN}═══ Credenciais do Admin ═══${NC}"
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

# Validar variáveis obrigatórias
echo -e "\n${BLUE}🔍 Validando variáveis obrigatórias...${NC}"
MISSING=""
for var in SITE_DOMAIN JWT_SECRET POSTGRES_PASSWORD ANON_KEY SERVICE_ROLE_KEY; do
  val=$(read_env "$var")
  if [ -z "$val" ] || [ "$val" = "CHANGE_ME" ]; then
    MISSING="$MISSING $var"
  fi
done
if [ -n "$MISSING" ]; then
  echo -e "${RED}❌ Variáveis obrigatórias faltando:$MISSING${NC}"
  exit 1
fi
echo -e "   ${GREEN}✅ Todas as variáveis obrigatórias configuradas${NC}"

# ════════════════════════════════════════════════════════════
# ETAPA 6 — Preparar Kong + Edge Functions
# ════════════════════════════════════════════════════════════
echo -e "\n${BLUE}🔧 Preparando configurações...${NC}"
bash render-kong-config.sh
bash sync-functions.sh "$INSTALL_DIR/supabase/functions" "volumes/functions"
echo -e "   ${GREEN}✅ Kong config e Functions prontos${NC}"

# ════════════════════════════════════════════════════════════
# ETAPA 7 — Subir banco e aguardar init
# ════════════════════════════════════════════════════════════
echo -e "\n${BLUE}🐘 Subindo PostgreSQL...${NC}"
docker compose up -d --build db

echo -e "${BLUE}⏳ Aguardando PostgreSQL ficar pronto...${NC}"
DB_USER=$(read_env "POSTGRES_USER"); DB_USER="${DB_USER:-supabase_admin}"
DB_NAME=$(read_env "POSTGRES_DB"); DB_NAME="${DB_NAME:-simply_db}"
for i in {1..60}; do
  docker exec simply-db pg_isready -U "$DB_USER" -d "$DB_NAME" -q 2>/dev/null && break
  [ "$i" = "60" ] && echo -e "${RED}❌ PostgreSQL não respondeu em 120s${NC}" && exit 1
  sleep 2
done
echo -e "   ${GREEN}✅ PostgreSQL respondendo${NC}"

# Aguardar init scripts (00-passwords.sh + 01-schema.sql)
echo -e "${BLUE}⏳ Aguardando init scripts (15s)...${NC}"
sleep 15

# ════════════════════════════════════════════════════════════
# ETAPA 8 — Sync passwords + Recovery SQL
# ════════════════════════════════════════════════════════════
echo -e "${BLUE}🔐 Sincronizando credenciais e roles...${NC}"
bash sync-db-passwords.sh || { echo -e "${RED}❌ Falha nas credenciais${NC}"; exit 1; }

echo -e "${BLUE}📋 Aplicando recovery SQL (idempotente)...${NC}"
POSTGRES_PASSWORD=$(read_env "POSTGRES_PASSWORD")
docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" simply-db \
  psql -v ON_ERROR_STOP=1 -w -h 127.0.0.1 -U supabase_admin -d "$DB_NAME" < sql/selfhosted-admin-recovery.sql || \
  echo -e "${YELLOW}⚠️  Recovery SQL com warnings (pode ser OK em fresh install)${NC}"

echo -e "   ${GREEN}✅ Schema, policies e triggers aplicados${NC}"

# ════════════════════════════════════════════════════════════
# ETAPA 9 — Subir todos os serviços
# ════════════════════════════════════════════════════════════
echo -e "\n${BLUE}🚀 Subindo todos os serviços...${NC}"
docker compose up -d --build --remove-orphans

echo -e "${BLUE}⏳ Aguardando serviços (25s)...${NC}"
sleep 25

# ════════════════════════════════════════════════════════════
# ETAPA 10 — Storage Buckets
# ════════════════════════════════════════════════════════════
echo -e "${BLUE}🪣 Configurando storage buckets...${NC}"
bash ensure-storage-buckets.sh || echo -e "${YELLOW}⚠️  Buckets pendentes (serão criados no próximo restart)${NC}"

# ════════════════════════════════════════════════════════════
# ETAPA 11 — Validação
# ════════════════════════════════════════════════════════════
echo -e "\n${BLUE}🧪 Validando instalação...${NC}"
if ! bash validate-install.sh; then
  echo -e "${YELLOW}⚠️  Reiniciando serviços e tentando novamente...${NC}"
  docker compose restart auth rest storage kong functions
  sleep 20
  bash validate-install.sh || { echo -e "${RED}❌ Validação falhou. Debug: docker compose logs --tail=50${NC}"; exit 1; }
fi

# ════════════════════════════════════════════════════════════
# ETAPA 12 — Criar admin
# ════════════════════════════════════════════════════════════
echo -e "\n${BLUE}👤 Criando usuário admin...${NC}"
bash create-admin.sh "$ADMIN_EMAIL" "$ADMIN_PASS"

# ════════════════════════════════════════════════════════════
# ETAPA 13 — SSL
# ════════════════════════════════════════════════════════════
SITE_DOMAIN=$(read_env "SITE_DOMAIN")
FRONTEND_PORT=$(read_env "FRONTEND_PORT"); FRONTEND_PORT="${FRONTEND_PORT:-3000}"
KONG_PORT=$(read_env "KONG_HTTP_PORT"); KONG_PORT="${KONG_PORT:-8000}"

if [ "$SKIP_SSL" != "true" ]; then
  echo ""
  read -p "Configurar SSL (Nginx + Let's Encrypt)? (s/N): " DO_SSL
  if [[ "$DO_SSL" =~ ^[sS]$ ]]; then
    bash setup-ssl.sh
  else
    echo -e "${YELLOW}ℹ️  SSL não configurado. Configure manualmente depois com: sudo bash setup-ssl.sh${NC}"
  fi
else
  echo -e "${YELLOW}ℹ️  SSL pulado (--skip-ssl). Configure depois com: sudo bash setup-ssl.sh${NC}"
fi

# ════════════════════════════════════════════════════════════
# RESULTADO FINAL
# ════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          ✅ Instalação concluída com sucesso!            ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║                                                          ║${NC}"
echo -e "${GREEN}║  Frontend:  http://localhost:${FRONTEND_PORT}                       ║${NC}"
echo -e "${GREEN}║  API:       http://localhost:${KONG_PORT}                       ║${NC}"
echo -e "${GREEN}║  Admin:     http://localhost:${FRONTEND_PORT}/admin                 ║${NC}"
echo -e "${GREEN}║                                                          ║${NC}"
echo -e "${GREEN}║  Com SSL:   https://${SITE_DOMAIN}                       ║${NC}"
echo -e "${GREEN}║  Admin:     https://${SITE_DOMAIN}/admin                 ║${NC}"
echo -e "${GREEN}║                                                          ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  Login Admin: ${ADMIN_EMAIL}                             ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║                                                          ║${NC}"
echo -e "${GREEN}║  Comandos úteis:                                         ║${NC}"
echo -e "${GREEN}║    bash status.sh          — ver status dos serviços     ║${NC}"
echo -e "${GREEN}║    bash logs.sh [servico]  — ver logs                    ║${NC}"
echo -e "${GREEN}║    bash redeploy.sh        — redeploy sem perder dados   ║${NC}"
echo -e "${GREEN}║    bash backup.sh          — backup do banco             ║${NC}"
echo -e "${GREEN}║    bash validate-install.sh — validar saúde              ║${NC}"
echo -e "${GREEN}║                                                          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo -e "\n${YELLOW}⚠️  Altere a senha do admin no primeiro acesso!${NC}"
echo -e "${YELLOW}⚠️  Configure DNS apontando para este servidor antes de usar SSL.${NC}"
