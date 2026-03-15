#!/bin/bash
# ============================================================
# Simply Imoveis - Instalador CLI Automatizado
# Versao: 2026-03-15-v16
# Requisitos: Ubuntu 24.04 + Docker (ou sera instalado)
# Uso: sudo bash install.sh [--clean] [--skip-ssl] [--non-interactive]
# ============================================================
set -euo pipefail

INSTALLER_VERSION="v16"

# Captura caminhos ANTES de qualquer modificacao no filesystem
_ORIG_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_ORIG_PROJECT_DIR="$(dirname "$_ORIG_SCRIPT_DIR")"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
BOLD='\033[1m'

INSTALL_DIR="/opt/simply-imoveis"
BACKUP_DIR="/opt/simply-imoveis/backups"
LOG_FILE="/var/log/simply-install-$(date +%Y%m%d-%H%M%S).log"
STEP_CURRENT=0
STEP_TOTAL=14

# ── Parse flags ──
FORCE_CLEAN=false
SKIP_SSL=false
NON_INTERACTIVE=false
ADMIN_EMAIL=""
ADMIN_PASS=""

for arg in "$@"; do
  case "$arg" in
    --clean) FORCE_CLEAN=true ;;
    --skip-ssl) SKIP_SSL=true ;;
    --non-interactive) NON_INTERACTIVE=true ;;
  esac
done

# ══════════════════════════════════════════════════════════════
# Helpers
# ══════════════════════════════════════════════════════════════
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

step() {
  STEP_CURRENT=$((STEP_CURRENT + 1))
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}  [${STEP_CURRENT}/${STEP_TOTAL}] ${BOLD}$1${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  log "STEP $STEP_CURRENT/$STEP_TOTAL: $1"
}

ok() { echo -e "   ${GREEN}✅ $1${NC}"; log "OK: $1"; }
warn() { echo -e "   ${YELLOW}⚠️  $1${NC}"; log "WARN: $1"; }

fail() {
  echo -e "   ${RED}❌ $1${NC}"
  log "FAIL: $1"
  echo ""
  echo -e "${RED}══════════════════════════════════════════════════════════${NC}"
  echo -e "${RED}  Instalação ABORTADA na etapa ${STEP_CURRENT}/${STEP_TOTAL}${NC}"
  echo -e "${RED}  Motivo: $1${NC}"
  echo -e "${RED}══════════════════════════════════════════════════════════${NC}"
  echo -e "${YELLOW}  Log completo: $LOG_FILE${NC}"
  echo -e "${YELLOW}  Debug: cd /opt/simply-imoveis/docker && docker compose logs --tail=100${NC}"
  exit 1
}

read_env() {
  grep -E "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"
}

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
  local cur
  cur=$(read_env "$var")
  [ -n "$cur" ] && [ "$cur" != "CHANGE_ME" ] && [ "$cur" != "gsk_XXXXXXXXXXXXXXXXXXXX" ] \
    && [ "$cur" != "seu-email@gmail.com" ] && [ "$cur" != "sua-senha-de-app" ] && return 0

  if [ "$NON_INTERACTIVE" = "true" ]; then
    [ -n "$default" ] && set_env "$var" "$default" && return 0
    [ "$required" = "true" ] && fail "Modo não-interativo: $var obrigatório sem valor padrão"
    return 0
  fi

  echo -e "\n${CYAN}${desc}${NC}"
  [ -n "$default" ] && echo -e "   Padrão: ${default}"
  [ "$required" = "true" ] && echo -e "   ${YELLOW}(obrigatório)${NC}"
  if [ "$secret" = "true" ]; then
    read -s -p "   > " val; echo ""
  else
    read -p "   > " val
  fi
  val="${val:-$default}"
  if [ "$required" = "true" ] && [ -z "$val" ]; then
    fail "Valor obrigatório para $var não informado"
  fi
  [ -n "$val" ] && set_env "$var" "$val"
}

gen_jwt() {
  local role_name="$1" secret="$2"
  local js_code
  js_code="$(cat <<JSCODE
const c=require('crypto');
const h=Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url');
const p=Buffer.from(JSON.stringify({ref:'simply',role:'${role_name}',iss:'supabase',iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+315360000})).toString('base64url');
const s=c.createHmac('sha256','${secret}').update(h+'.'+p).digest('base64url');
console.log(h+'.'+p+'.'+s);
JSCODE
)"
  if command -v node &>/dev/null; then
    node -e "$js_code"
  else
    docker run --rm node:20-alpine node -e "$js_code"
  fi
}

detect_server_ip() {
  # Tentar obter IP público
  local ip=""
  ip=$(curl -sS -m 5 https://ifconfig.me 2>/dev/null || true)
  [ -z "$ip" ] && ip=$(curl -sS -m 5 https://api.ipify.org 2>/dev/null || true)
  [ -z "$ip" ] && ip=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
  echo "${ip:-unknown}"
}

# ══════════════════════════════════════════════════════════════
# Banner
# ══════════════════════════════════════════════════════════════
clear 2>/dev/null || true
echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                                                          ║"
echo "║     Simply Imóveis - Instalador CLI ${INSTALLER_VERSION}              ║"
echo "║     Sistema de Gestão Imobiliária Self-Hosted            ║"
echo "║                                                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

mkdir -p "$(dirname "$LOG_FILE")"
log "=== Instalação iniciada: $INSTALLER_VERSION ==="
log "Args: $*"

# ══════════════════════════════════════════════════════════════
# ETAPA 1 - Verificações de privilégio e SO
# ══════════════════════════════════════════════════════════════
step "Verificações do sistema"

[ "$EUID" -ne 0 ] && fail "Execute com sudo: sudo bash install.sh"

# Verificar Ubuntu
if [ -f /etc/os-release ]; then
  . /etc/os-release
  echo -e "   OS: ${PRETTY_NAME:-unknown}"
  log "OS: ${PRETTY_NAME:-unknown}"
  if [[ "${ID:-}" != "ubuntu" ]]; then
    warn "Sistema não é Ubuntu. A instalação pode funcionar mas não é garantida."
  fi
  if [[ "${VERSION_ID:-}" != "24.04" && "${VERSION_ID:-}" != "22.04" ]]; then
    warn "Versão ${VERSION_ID:-unknown} detectada. Recomendado: Ubuntu 24.04 LTS"
  fi
else
  warn "Não foi possível detectar o sistema operacional"
fi

# Requisitos mínimos: RAM
TOTAL_RAM_MB=$(free -m 2>/dev/null | awk '/Mem:/{print $2}' || echo "0")
if [ "$TOTAL_RAM_MB" -lt 1800 ]; then
  fail "RAM insuficiente: ${TOTAL_RAM_MB}MB (mínimo 2GB)"
elif [ "$TOTAL_RAM_MB" -lt 3800 ]; then
  warn "RAM: ${TOTAL_RAM_MB}MB (recomendado 4GB+)"
else
  ok "RAM: ${TOTAL_RAM_MB}MB"
fi

# Requisitos mínimos: Disco
DISK_AVAIL_GB=$(df -BG / 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G' || echo "0")
if [ "${DISK_AVAIL_GB:-0}" -lt 5 ]; then
  fail "Disco insuficiente: ${DISK_AVAIL_GB}GB livres (mínimo 5GB)"
elif [ "${DISK_AVAIL_GB:-0}" -lt 10 ]; then
  warn "Disco: ${DISK_AVAIL_GB}GB livres (recomendado 10GB+)"
else
  ok "Disco: ${DISK_AVAIL_GB}GB livres"
fi

# Requisitos mínimos: CPU
CPU_CORES=$(nproc 2>/dev/null || echo "1")
if [ "$CPU_CORES" -lt 1 ]; then
  fail "CPU insuficiente: ${CPU_CORES} cores (mínimo 1)"
elif [ "$CPU_CORES" -lt 2 ]; then
  warn "CPU: ${CPU_CORES} core(s) (recomendado 2+)"
else
  ok "CPU: ${CPU_CORES} cores"
fi

# Portas
for port in 5432 3000 8000 80 443; do
  if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "simply-"; then
      ok "Porta $port em uso por container Simply (será recriado)"
    else
      case "$port" in
        80|443)
          # Nginx pode estar rodando, é esperado
          PROC=$(ss -tlnp 2>/dev/null | grep ":${port} " | grep -oP 'users:\(\("\K[^"]+' || echo "desconhecido")
          warn "Porta $port em uso por: $PROC (esperado para nginx)"
          ;;
        *)
          fail "Porta $port em uso por processo externo. Libere antes de instalar."
          ;;
      esac
    fi
  fi
done

ok "Verificações do sistema concluídas"

# ══════════════════════════════════════════════════════════════
# ETAPA 2 - Validação do pacote fonte
# ══════════════════════════════════════════════════════════════
step "Validação do pacote fonte"

REQUIRED_SOURCE_FILES=(
  "docker/docker-compose.yml"
  "docker/Dockerfile"
  "docker/.env.example"
  "docker/sql/selfhosted-admin-recovery.sql"
  "docker/sql/bootstrap-storage.sql"
  "docker/bootstrap-db.sh"
  "docker/sync-db-passwords.sh"
  "docker/ensure-storage-buckets.sh"
  "docker/sync-functions.sh"
  "docker/render-kong-config.sh"
  "docker/render-functions-main.sh"
  "docker/create-admin.sh"
  "docker/validate-install.sh"
  "docker/full-wipe.sh"
  "docker/volumes/db/init/00-passwords.sh"
  "docker/volumes/db/init/01-schema.sql"
  "docker/volumes/kong/kong.yml.template"
  "supabase/functions/chat/index.ts"
  "supabase/functions/admin-crud/index.ts"
  "supabase/functions/create-admin-user/index.ts"
  "supabase/functions/notify-telegram/index.ts"
  "supabase/functions/ai-insights/index.ts"
)

SRC_MISSING=0
for f in "${REQUIRED_SOURCE_FILES[@]}"; do
  if [ ! -f "$_ORIG_PROJECT_DIR/$f" ]; then
    echo -e "   ${RED}Ausente: $f${NC}"
    SRC_MISSING=$((SRC_MISSING + 1))
  fi
done
[ "$SRC_MISSING" -gt 0 ] && fail "$SRC_MISSING arquivo(s) ausente(s) no pacote fonte"
ok "Pacote fonte validado (${#REQUIRED_SOURCE_FILES[@]} arquivos)"

# ══════════════════════════════════════════════════════════════
# ETAPA 3 - Instalação de dependências do host
# ══════════════════════════════════════════════════════════════
step "Instalação de dependências"

echo -e "   Atualizando pacotes do sistema..."
apt-get update -qq >/dev/null 2>&1 || warn "apt-get update falhou (continuando)"
apt-get install -y -qq rsync curl openssl jq nginx certbot python3-certbot-nginx \
  ca-certificates gnupg lsb-release >/dev/null 2>&1 || warn "Alguns pacotes podem não ter sido instalados"

# Docker
if ! command -v docker &>/dev/null; then
  echo -e "   ${BLUE}Instalando Docker Engine...${NC}"
  curl -fsSL https://get.docker.com | sh >> "$LOG_FILE" 2>&1 || fail "Falha ao instalar Docker"
  systemctl enable docker >/dev/null 2>&1 && systemctl start docker >/dev/null 2>&1
  ok "Docker instalado: $(docker --version 2>/dev/null)"
else
  ok "Docker: $(docker --version 2>/dev/null | head -1)"
fi

# Docker Compose
if ! docker compose version &>/dev/null; then
  apt-get install -y -qq docker-compose-plugin >/dev/null 2>&1 || fail "Falha ao instalar Docker Compose"
fi
docker info >/dev/null 2>&1 || fail "Docker não está funcionando"
ok "Docker Compose: $(docker compose version --short 2>/dev/null)"

# ══════════════════════════════════════════════════════════════
# ETAPA 4 - Snapshot seguro + limpeza
# ══════════════════════════════════════════════════════════════
step "Preparação do ambiente"

SAFE_SOURCE="/tmp/simply-install-source-$$"
rm -rf "$SAFE_SOURCE"
mkdir -p "$SAFE_SOURCE"
rsync -a --exclude='node_modules' --exclude='.git' "$_ORIG_PROJECT_DIR/" "$SAFE_SOURCE/" 2>/dev/null || \
  cp -r "$_ORIG_PROJECT_DIR/." "$SAFE_SOURCE/" 2>/dev/null || true

[ ! -f "$SAFE_SOURCE/docker/docker-compose.yml" ] && fail "Falha ao criar snapshot do pacote fonte"
ok "Snapshot criado em $SAFE_SOURCE"

# Detecção de instalação anterior
EXISTING=$(docker ps -a --filter "name=simply-" -q 2>/dev/null | wc -l || echo "0")
if [ "$FORCE_CLEAN" = "true" ]; then
  echo -e "   ${YELLOW}Full wipe (--clean)...${NC}"
  bash "$SAFE_SOURCE/docker/full-wipe.sh" --force 2>/dev/null || true
  ok "Limpeza completa realizada"
elif [ "$EXISTING" -gt 0 ]; then
  echo -e "   ${YELLOW}Instalação anterior detectada ($EXISTING containers).${NC}"
  if [ "$NON_INTERACTIVE" = "true" ]; then
    bash "$SAFE_SOURCE/docker/full-wipe.sh" --force 2>/dev/null || true
  else
    read -p "   Limpar tudo e reinstalar? (S/n): " DO_CLEAN
    if [[ ! "$DO_CLEAN" =~ ^[nN]$ ]]; then
      bash "$SAFE_SOURCE/docker/full-wipe.sh" --force 2>/dev/null || true
    fi
  fi
  ok "Ambiente limpo"
fi

# ══════════════════════════════════════════════════════════════
# ETAPA 5 - Copiar para /opt/simply-imoveis
# ══════════════════════════════════════════════════════════════
step "Instalação dos arquivos"

cd /
mkdir -p "$INSTALL_DIR"
rsync -a --delete --exclude='node_modules' --exclude='docker/.env' --exclude='.git' \
  "$SAFE_SOURCE/" "$INSTALL_DIR/"

cd "$INSTALL_DIR/docker"
chmod +x ./*.sh 2>/dev/null || true
chmod +x volumes/db/init/*.sh 2>/dev/null || true
mkdir -p "$BACKUP_DIR"

ok "Projeto instalado em $INSTALL_DIR"

# ══════════════════════════════════════════════════════════════
# ETAPA 6 - Configuração .env
# ══════════════════════════════════════════════════════════════
step "Configuração de variáveis de ambiente"

[ ! -f .env ] && cp .env.example .env

# Auto-geração de credenciais
echo -e "   ${BLUE}Gerando credenciais seguras...${NC}"

CURRENT_JWT=$(read_env "JWT_SECRET")
if [ -z "$CURRENT_JWT" ] || [ "$CURRENT_JWT" = "super-secret-jwt-token-with-at-least-32-characters-long" ]; then
  set_env "JWT_SECRET" "$(openssl rand -base64 32)"
  ok "JWT_SECRET gerado"
else
  ok "JWT_SECRET existente preservado"
fi

CURRENT_PG=$(read_env "POSTGRES_PASSWORD")
if [ -z "$CURRENT_PG" ] || [ "$CURRENT_PG" = "SuaSenhaForteAqui123!" ]; then
  set_env "POSTGRES_PASSWORD" "$(openssl rand -base64 24 | tr -d '=/+')"
  ok "POSTGRES_PASSWORD gerado"
else
  ok "POSTGRES_PASSWORD existente preservado"
fi
[ -z "$(read_env "POSTGRES_USER")" ] && set_env "POSTGRES_USER" "supabase_admin"

CURRENT_ANON=$(read_env "ANON_KEY")
if [ -z "$CURRENT_ANON" ] || [ "$CURRENT_ANON" = "CHANGE_ME" ]; then
  JWT_SECRET=$(read_env "JWT_SECRET")
  ANON=$(gen_jwt "anon" "$JWT_SECRET")
  SERVICE=$(gen_jwt "service_role" "$JWT_SECRET")
  [ -z "$ANON" ] || [ -z "$SERVICE" ] && fail "Falha ao gerar tokens JWT"
  set_env "ANON_KEY" "$ANON"
  set_env "SERVICE_ROLE_KEY" "$SERVICE"
  ok "ANON_KEY + SERVICE_ROLE_KEY gerados"
else
  ok "JWT tokens existentes preservados"
fi

# Configurações interativas
echo -e "\n${CYAN}=== Configurações do Site ===${NC}"
prompt_config "SITE_DOMAIN" "Domínio do site (ex: simplyimoveis.com.br)" "simplyimoveis.com.br" "false" "true"

echo -e "\n${CYAN}=== SMTP (Email) ===${NC}"
prompt_config "SMTP_HOST" "Servidor SMTP" "smtp.gmail.com"
prompt_config "SMTP_PORT" "Porta SMTP" "587"
prompt_config "SMTP_USER" "Email SMTP"
prompt_config "SMTP_PASS" "Senha SMTP - App Password" "" "true"
prompt_config "SMTP_SENDER_NAME" "Nome do remetente" "Simply Imoveis"
prompt_config "SMTP_ADMIN_EMAIL" "Email do admin" "admin@simplyimoveis.com.br"

echo -e "\n${CYAN}=== Integrações ===${NC}"
prompt_config "GROQ_API_KEY" "Chave Groq API (chat IA)" "" "true"

echo -e "\n${CYAN}=== Telegram (opcional) ===${NC}"
prompt_config "TELEGRAM_BOT_TOKEN" "Telegram Bot Token"
prompt_config "TELEGRAM_CHAT_ID" "Telegram Chat ID"

# Credenciais admin
echo -e "\n${CYAN}=== Credenciais do Administrador ===${NC}"
if [ "$NON_INTERACTIVE" = "true" ]; then
  ADMIN_EMAIL="${ADMIN_EMAIL:-admin@simplyimoveis.com.br}"
  ADMIN_PASS="${ADMIN_PASS:-SimplyAdmin2026!}"
  warn "Modo não-interativo: admin=${ADMIN_EMAIL} (altere a senha após login)"
else
  default_admin="$(read_env "SMTP_ADMIN_EMAIL")"
  default_admin="${default_admin:-admin@simplyimoveis.com.br}"
  read -p "   Email admin [$default_admin]: " ADMIN_EMAIL
  ADMIN_EMAIL="${ADMIN_EMAIL:-$default_admin}"
  while [[ ! "$ADMIN_EMAIL" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; do
    read -p "   Email inválido, tente novamente: " ADMIN_EMAIL
  done
  while true; do
    read -s -p "   Senha admin (mín 8 caracteres): " ADMIN_PASS; echo ""
    [ ${#ADMIN_PASS} -ge 8 ] && break
    echo -e "   ${YELLOW}Senha muito curta (mínimo 8 caracteres)${NC}"
  done
fi

# Validar variáveis obrigatórias
echo -e "\n   ${BLUE}Validando variáveis obrigatórias...${NC}"
MISSING=""
for var in SITE_DOMAIN JWT_SECRET POSTGRES_PASSWORD ANON_KEY SERVICE_ROLE_KEY; do
  val=$(read_env "$var")
  [ -z "$val" ] || [ "$val" = "CHANGE_ME" ] && MISSING="$MISSING $var"
done
[ -n "$MISSING" ] && fail "Variáveis faltando:$MISSING"
ok "Todas as variáveis configuradas"

# ══════════════════════════════════════════════════════════════
# ETAPA 7 - Kong + Edge Functions
# ══════════════════════════════════════════════════════════════
step "Configuração Kong + Edge Functions"

bash render-kong-config.sh >> "$LOG_FILE" 2>&1 || fail "Falha ao renderizar kong.yml"
ok "Kong config renderizado"

bash sync-functions.sh "$INSTALL_DIR/supabase/functions" "volumes/functions" >> "$LOG_FILE" 2>&1 || fail "Falha ao sincronizar Edge Functions"
ok "Edge Functions sincronizadas"

# ══════════════════════════════════════════════════════════════
# ETAPA 8 - Subir PostgreSQL
# ══════════════════════════════════════════════════════════════
step "Inicialização do PostgreSQL"

docker compose up -d --build db >> "$LOG_FILE" 2>&1 || fail "Falha ao iniciar container db"

DB_USER=$(read_env "POSTGRES_USER"); DB_USER="${DB_USER:-supabase_admin}"
DB_NAME=$(read_env "POSTGRES_DB"); DB_NAME="${DB_NAME:-simply_db}"

echo -e "   Aguardando PostgreSQL ficar pronto..."
for i in $(seq 1 90); do
  if docker exec simply-db pg_isready -U "$DB_USER" -d "$DB_NAME" -q 2>/dev/null; then
    break
  fi
  [ "$i" = "90" ] && fail "PostgreSQL não respondeu em 180s"
  sleep 2
done
ok "PostgreSQL pronto"

# ══════════════════════════════════════════════════════════════
# ETAPA 9 - Bootstrap DB + Storage
# ══════════════════════════════════════════════════════════════
step "Bootstrap do banco e storage"

if ! bash bootstrap-db.sh >> "$LOG_FILE" 2>&1; then
  echo -e "   ${YELLOW}Primeira tentativa falhou, aguardando 10s e tentando novamente...${NC}"
  sleep 10
  bash bootstrap-db.sh >> "$LOG_FILE" 2>&1 || fail "Falha no bootstrap do banco/storage. Veja: $LOG_FILE"
fi
ok "Schema, tipos, tabelas, RLS, policies e storage configurados"

# ══════════════════════════════════════════════════════════════
# ETAPA 10 - Subir todos os serviços
# ══════════════════════════════════════════════════════════════
step "Inicialização de todos os serviços"

docker compose up -d --build --remove-orphans >> "$LOG_FILE" 2>&1 || fail "Falha ao iniciar serviços Docker"

echo -e "   Aguardando serviços estabilizarem (30s)..."
sleep 30

# Verificar se todos os containers estão rodando
FAILED_CONTAINERS=""
for c in simply-db simply-auth simply-rest simply-storage simply-kong simply-functions simply-frontend; do
  st=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo "missing")
  rs=$(docker inspect -f '{{.State.Restarting}}' "$c" 2>/dev/null || echo "false")
  if [ "$st" = "running" ] && [ "$rs" != "true" ]; then
    ok "$c rodando"
  else
    FAILED_CONTAINERS="$FAILED_CONTAINERS $c($st)"
  fi
done

if [ -n "$FAILED_CONTAINERS" ]; then
  warn "Containers com problema:$FAILED_CONTAINERS — reiniciando..."
  docker compose restart auth rest storage kong functions >> "$LOG_FILE" 2>&1
  sleep 20

  # Re-verificar
  STILL_FAILED=""
  for c in simply-db simply-auth simply-rest simply-storage simply-kong simply-functions simply-frontend; do
    st=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo "missing")
    [ "$st" != "running" ] && STILL_FAILED="$STILL_FAILED $c"
  done
  [ -n "$STILL_FAILED" ] && fail "Containers ainda falhando após restart:$STILL_FAILED"
  ok "Todos os containers recuperados após restart"
fi

# ══════════════════════════════════════════════════════════════
# ETAPA 11 - Validação do stack
# ══════════════════════════════════════════════════════════════
step "Validação do stack"

if ! bash validate-install.sh >> "$LOG_FILE" 2>&1; then
  warn "Primeira validação falhou — reiniciando serviços..."
  docker compose restart auth rest storage kong functions >> "$LOG_FILE" 2>&1
  sleep 20
  if ! bash validate-install.sh >> "$LOG_FILE" 2>&1; then
    fail "Validação do stack falhou. Log: $LOG_FILE"
  fi
fi
ok "Stack validado com sucesso"

# ══════════════════════════════════════════════════════════════
# ETAPA 12 - Criar admin
# ══════════════════════════════════════════════════════════════
step "Criação do administrador"

if bash create-admin.sh "$ADMIN_EMAIL" "$ADMIN_PASS" >> "$LOG_FILE" 2>&1; then
  ok "Admin criado: $ADMIN_EMAIL"
else
  warn "Falha ao criar admin na primeira tentativa. Tentando novamente em 15s..."
  sleep 15
  bash create-admin.sh "$ADMIN_EMAIL" "$ADMIN_PASS" >> "$LOG_FILE" 2>&1 || fail "Falha ao criar admin. Log: $LOG_FILE"
  ok "Admin criado na segunda tentativa: $ADMIN_EMAIL"
fi

# ══════════════════════════════════════════════════════════════
# ETAPA 13 - SSL (Nginx + Let's Encrypt)
# ══════════════════════════════════════════════════════════════
step "Configuração SSL / Nginx"

SITE_DOMAIN=$(read_env "SITE_DOMAIN")
FRONTEND_PORT=$(read_env "FRONTEND_PORT"); FRONTEND_PORT="${FRONTEND_PORT:-3000}"
KONG_PORT=$(read_env "KONG_HTTP_PORT"); KONG_PORT="${KONG_PORT:-8000}"

if [ "$SKIP_SSL" = "true" ]; then
  warn "SSL pulado (--skip-ssl). Configure depois: sudo bash setup-ssl.sh"
elif [ "$NON_INTERACTIVE" = "true" ]; then
  warn "SSL pulado (modo não-interativo). Configure depois: sudo bash setup-ssl.sh"
else
  read -p "   Configurar SSL (Nginx + Let's Encrypt)? (s/N): " DO_SSL
  if [[ "$DO_SSL" =~ ^[sS]$ ]]; then
    if bash setup-ssl.sh >> "$LOG_FILE" 2>&1; then
      ok "SSL configurado para $SITE_DOMAIN"
    else
      warn "SSL falhou (DNS pode não estar apontando). Configure depois: sudo bash setup-ssl.sh"
    fi
  else
    warn "SSL não configurado. Rode depois: sudo bash setup-ssl.sh"
  fi
fi

# ══════════════════════════════════════════════════════════════
# ETAPA 14 - Health Check final
# ══════════════════════════════════════════════════════════════
step "Health check final"

# Testar endpoints
HEALTH_ERRORS=0

# Frontend
FE_ST=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" "http://127.0.0.1:${FRONTEND_PORT}/" 2>/dev/null || echo "000")
[ "$FE_ST" = "200" ] && ok "Frontend: HTTP 200" || { warn "Frontend: HTTP $FE_ST"; HEALTH_ERRORS=$((HEALTH_ERRORS + 1)); }

# Auth API
ANON_KEY=$(read_env "ANON_KEY")
AUTH_ST=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" "http://127.0.0.1:${KONG_PORT}/auth/v1/settings" -H "apikey: ${ANON_KEY}" 2>/dev/null || echo "000")
[ "$AUTH_ST" = "200" ] && ok "Auth API: HTTP 200" || { warn "Auth API: HTTP $AUTH_ST"; HEALTH_ERRORS=$((HEALTH_ERRORS + 1)); }

# REST API
REST_ST=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" "http://127.0.0.1:${KONG_PORT}/rest/v1/" -H "apikey: ${ANON_KEY}" 2>/dev/null || echo "000")
[ "$REST_ST" = "200" ] && ok "REST API: HTTP 200" || { warn "REST API: HTTP $REST_ST"; HEALTH_ERRORS=$((HEALTH_ERRORS + 1)); }

# Storage API
SERVICE_ROLE_KEY=$(read_env "SERVICE_ROLE_KEY")
STORAGE_ST=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" "http://127.0.0.1:${KONG_PORT}/storage/v1/bucket" -H "apikey: ${ANON_KEY}" -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" 2>/dev/null || echo "000")
[ "$STORAGE_ST" = "200" ] && ok "Storage API: HTTP 200" || { warn "Storage API: HTTP $STORAGE_ST"; HEALTH_ERRORS=$((HEALTH_ERRORS + 1)); }

# Edge Functions
FUNC_ST=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" -X OPTIONS "http://127.0.0.1:${KONG_PORT}/functions/v1/admin-crud" -H "apikey: ${ANON_KEY}" 2>/dev/null || echo "000")
case "$FUNC_ST" in
  200|204) ok "Edge Functions: HTTP $FUNC_ST (CORS OK)" ;;
  *) warn "Edge Functions: HTTP $FUNC_ST"; HEALTH_ERRORS=$((HEALTH_ERRORS + 1)) ;;
esac

# Login test
LOGIN_ST=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" -X POST \
  "http://127.0.0.1:${KONG_PORT}/auth/v1/token?grant_type=password" \
  -H "apikey: ${ANON_KEY}" -H "Content-Type: application/json" \
  -d "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"$(printf '%s' "$ADMIN_PASS" | sed 's/"/\\"/g')\"}" 2>/dev/null || echo "000")
[ "$LOGIN_ST" = "200" ] && ok "Login admin: autenticação OK" || { warn "Login admin: HTTP $LOGIN_ST"; HEALTH_ERRORS=$((HEALTH_ERRORS + 1)); }

# Containers finais
CONTAINERS_RUNNING=$(docker ps --filter "name=simply-" --format "{{.Names}}: {{.Status}}" 2>/dev/null)

# Detectar IP
SERVER_IP=$(detect_server_ip)

# Cleanup
rm -rf "$SAFE_SOURCE" 2>/dev/null || true

# ══════════════════════════════════════════════════════════════
# RESULTADO FINAL
# ══════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}                                                              ${NC}"
if [ "$HEALTH_ERRORS" -eq 0 ]; then
  echo -e "${GREEN}   ✅  INSTALAÇÃO CONCLUÍDA COM SUCESSO!                      ${NC}"
else
  echo -e "${YELLOW}   ⚠️  INSTALAÇÃO CONCLUÍDA COM $HEALTH_ERRORS ALERTA(S)        ${NC}"
fi
echo -e "${GREEN}                                                              ${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}  ┌─────────────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}  │  INFORMAÇÕES DO SERVIDOR                               │${NC}"
echo -e "${CYAN}  ├─────────────────────────────────────────────────────────┤${NC}"
echo -e "${CYAN}  │  IP:             ${GREEN}${SERVER_IP}${NC}"
echo -e "${CYAN}  │  Domínio:        ${GREEN}${SITE_DOMAIN}${NC}"
echo -e "${CYAN}  │  Frontend:       ${GREEN}http://127.0.0.1:${FRONTEND_PORT}${NC}"
echo -e "${CYAN}  │  API Gateway:    ${GREEN}http://127.0.0.1:${KONG_PORT}${NC}"
echo -e "${CYAN}  │  Admin Panel:    ${GREEN}http://127.0.0.1:${FRONTEND_PORT}/admin${NC}"
echo -e "${CYAN}  │  Banco:          ${GREEN}127.0.0.1:5432${NC}"
echo -e "${CYAN}  ├─────────────────────────────────────────────────────────┤${NC}"
echo -e "${CYAN}  │  LOGIN ADMIN                                           │${NC}"
echo -e "${CYAN}  ├─────────────────────────────────────────────────────────┤${NC}"
echo -e "${CYAN}  │  Email:          ${GREEN}${ADMIN_EMAIL}${NC}"
echo -e "${CYAN}  │  Senha:          ${GREEN}(informada durante instalação)${NC}"
echo -e "${CYAN}  ├─────────────────────────────────────────────────────────┤${NC}"
echo -e "${CYAN}  │  CONTAINERS                                            │${NC}"
echo -e "${CYAN}  ├─────────────────────────────────────────────────────────┤${NC}"
while IFS= read -r line; do
  echo -e "${CYAN}  │  ${GREEN}${line}${NC}"
done <<< "$CONTAINERS_RUNNING"
echo -e "${CYAN}  └─────────────────────────────────────────────────────────┘${NC}"
echo ""
echo -e "${YELLOW}  ┌─────────────────────────────────────────────────────────┐${NC}"
echo -e "${YELLOW}  │  PRÓXIMOS PASSOS                                       │${NC}"
echo -e "${YELLOW}  ├─────────────────────────────────────────────────────────┤${NC}"
echo -e "${YELLOW}  │  1. Configure DNS: ${SITE_DOMAIN} → ${SERVER_IP}${NC}"
echo -e "${YELLOW}  │  2. Ative SSL: sudo bash setup-ssl.sh                  │${NC}"
echo -e "${YELLOW}  │  3. Acesse: https://${SITE_DOMAIN}/admin               │${NC}"
echo -e "${YELLOW}  │  4. Altere a senha do admin no primeiro acesso!        │${NC}"
echo -e "${YELLOW}  └─────────────────────────────────────────────────────────┘${NC}"
echo ""
echo -e "${CYAN}  Comandos úteis:${NC}"
echo -e "    ${GREEN}cd $INSTALL_DIR/docker${NC}"
echo -e "    ${GREEN}bash status.sh${NC}               — status dos serviços"
echo -e "    ${GREEN}bash health-check.sh${NC}          — diagnóstico completo"
echo -e "    ${GREEN}bash backup.sh${NC}                — backup do banco"
echo -e "    ${GREEN}bash restore.sh <arquivo>${NC}     — restaurar backup"
echo -e "    ${GREEN}bash update.sh${NC}                — atualizar sistema"
echo -e "    ${GREEN}bash quick-update.sh${NC}          — atualização rápida (GitHub)"
echo -e "    ${GREEN}bash logs.sh [servico]${NC}        — ver logs"
echo -e "    ${GREEN}bash validate-install.sh${NC}      — validar stack"
echo -e "    ${GREEN}bash validate-install.sh --public${NC} — validar URL pública"
echo ""
echo -e "${CYAN}  Log desta instalação: ${GREEN}${LOG_FILE}${NC}"
echo ""

log "=== Instalação concluída com $HEALTH_ERRORS alerta(s) ==="
