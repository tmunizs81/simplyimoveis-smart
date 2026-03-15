#!/bin/bash
# ============================================================
# Simply Imoveis - Instalador para Ubuntu 24.04 LTS
# Versao: 2026-03-15-v15
# Uso: sudo bash install.sh [--clean] [--skip-ssl]
# ============================================================
set -euo pipefail

# Captura caminhos ANTES de qualquer modificacao no filesystem
_ORIG_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_ORIG_PROJECT_DIR="$(dirname "$_ORIG_SCRIPT_DIR")"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${BLUE}"
echo "======================================================"
echo "     Simply Imoveis - Instalador v15"
echo "     Ubuntu 24.04 LTS + Docker"
echo "======================================================"
echo -e "${NC}"

[ "$EUID" -ne 0 ] && echo -e "${RED}Erro: Execute com sudo: sudo bash install.sh${NC}" && exit 1

# -- Parse flags --
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

# -- Helpers --
read_env() {
  grep -E "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"
}

set_env() {
  local k="$1"
  local v="$2"
  if grep -qE "^${k}=" .env 2>/dev/null; then
    sed -i "s|^${k}=.*|${k}=\"${v}\"|" .env
  else
    echo "${k}=\"${v}\"" >> .env
  fi
}

prompt_config() {
  local var="$1"
  local desc="$2"
  local default="${3:-}"
  local secret="${4:-false}"
  local required="${5:-false}"
  local cur
  cur=$(read_env "$var")
  [ -n "$cur" ] && [ "$cur" != "CHANGE_ME" ] && [ "$cur" != "gsk_XXXXXXXXXXXXXXXXXXXX" ] \
    && [ "$cur" != "seu-email@gmail.com" ] && [ "$cur" != "sua-senha-de-app" ] && return 0
  echo -e "\n${CYAN}${desc}${NC}"
  [ -n "$default" ] && echo -e "   Padrao: ${default}"
  [ "$required" = "true" ] && echo -e "   ${YELLOW}(obrigatorio)${NC}"
  if [ "$secret" = "true" ]; then
    read -s -p "   > " val
    echo ""
  else
    read -p "   > " val
  fi
  val="${val:-$default}"
  if [ "$required" = "true" ] && [ -z "$val" ]; then
    echo -e "${RED}Erro: Valor obrigatorio. Abortando.${NC}"
    exit 1
  fi
  [ -n "$val" ] && set_env "$var" "$val"
}

gen_jwt() {
  local role_name="$1"
  local secret="$2"
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

INSTALL_DIR="/opt/simply-imoveis"

# ==============================================================
# ETAPA 1 - Validacao do pacote fonte
# ==============================================================
echo -e "${BLUE}Validando pacote fonte...${NC}"
REQUIRED_SOURCE_FILES=(
  "docker/docker-compose.yml"
  "docker/Dockerfile"
  "docker/.env.example"
  "docker/sql/selfhosted-admin-recovery.sql"
  "docker/sql/bootstrap-storage.sql"
  "docker/bootstrap-db.sh"
  "docker/reset-db.sh"
  "docker/validate.sh"
  "docker/validate-install.sh"
  "docker/sync-db-passwords.sh"
  "docker/ensure-storage-buckets.sh"
  "docker/sync-functions.sh"
  "docker/render-kong-config.sh"
  "docker/render-functions-main.sh"
  "docker/create-admin.sh"
  "docker/full-wipe.sh"
  "docker/volumes/db/init/00-passwords.sh"
  "docker/volumes/db/init/01-schema.sql"
  "docker/volumes/kong/kong.yml.template"
  "supabase/functions/chat/index.ts"
  "supabase/functions/admin-crud/index.ts"
  "supabase/functions/create-admin-user/index.ts"
  "supabase/functions/notify-telegram/index.ts"
)
SRC_MISSING=0
for f in "${REQUIRED_SOURCE_FILES[@]}"; do
  if [ ! -f "$_ORIG_PROJECT_DIR/$f" ]; then
    echo -e "   ${RED}Ausente: $_ORIG_PROJECT_DIR/$f${NC}"
    SRC_MISSING=$((SRC_MISSING + 1))
  fi
done
if [ "$SRC_MISSING" -gt 0 ]; then
  echo -e "${RED}Erro: $SRC_MISSING arquivo(s) ausente(s) no pacote fonte. Abortando.${NC}"
  exit 1
fi
echo -e "   ${GREEN}OK: Pacote fonte validado (${#REQUIRED_SOURCE_FILES[@]} arquivos)${NC}"

# ==============================================================
# ETAPA 2 - Verificacoes do host
# ==============================================================
echo -e "${BLUE}Verificando sistema...${NC}"
[ -f /etc/os-release ] && . /etc/os-release && echo -e "   OS: $PRETTY_NAME"

for port in 5432 3000 8000; do
  if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "simply-"; then
      echo -e "${RED}Erro: Porta $port em uso por processo externo. Libere antes de instalar.${NC}"
      exit 1
    fi
  fi
done

# ==============================================================
# ETAPA 3 - Snapshot + Full Wipe (se necessario)
# ==============================================================
SAFE_SOURCE="/tmp/simply-install-source"
rm -rf "$SAFE_SOURCE"
echo -e "${BLUE}Snapshot do projeto em $SAFE_SOURCE...${NC}"
mkdir -p "$SAFE_SOURCE"
rsync -a --exclude='node_modules' "$_ORIG_PROJECT_DIR/" "$SAFE_SOURCE/" 2>/dev/null || \
  cp -r "$_ORIG_PROJECT_DIR/." "$SAFE_SOURCE/" 2>/dev/null || true

if [ ! -f "$SAFE_SOURCE/docker/docker-compose.yml" ]; then
  echo -e "${RED}Erro: Falha no snapshot${NC}"
  exit 1
fi
echo -e "   ${GREEN}OK: Snapshot criado${NC}"

EXISTING=$(docker ps -a --filter "name=simply-" -q 2>/dev/null | wc -l || echo "0")
if [ "$FORCE_CLEAN" = "true" ]; then
  echo -e "${BLUE}Full wipe (--clean)...${NC}"
  bash "$SAFE_SOURCE/docker/full-wipe.sh" --force 2>/dev/null || true
elif [ "$EXISTING" -gt 0 ]; then
  echo -e "${YELLOW}Instalacao anterior detectada ($EXISTING containers).${NC}"
  read -p "Limpar tudo e reinstalar? (S/n): " DO_CLEAN
  if [[ ! "$DO_CLEAN" =~ ^[nN]$ ]]; then
    bash "$SAFE_SOURCE/docker/full-wipe.sh" --force 2>/dev/null || true
  fi
fi

# ==============================================================
# ETAPA 4 - Dependencias do host
# ==============================================================
echo -e "\n${BLUE}Instalando dependencias do sistema...${NC}"
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq rsync curl openssl jq nginx certbot python3-certbot-nginx ca-certificates gnupg lsb-release >/dev/null 2>&1

if ! command -v docker &>/dev/null; then
  echo -e "${BLUE}Instalando Docker Engine...${NC}"
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker && systemctl start docker
  echo -e "   ${GREEN}OK: Docker instalado${NC}"
else
  echo -e "   ${GREEN}OK: Docker: $(docker --version)${NC}"
fi
docker compose version &>/dev/null || apt-get install -y -qq docker-compose-plugin >/dev/null 2>&1
docker info >/dev/null 2>&1 || { echo -e "${RED}Erro: Docker nao funciona${NC}"; exit 1; }
echo -e "   ${GREEN}OK: Docker Compose: $(docker compose version --short)${NC}"

# ==============================================================
# ETAPA 5 - Copiar para /opt/simply-imoveis
# ==============================================================
cd /
mkdir -p "$INSTALL_DIR"
echo -e "${BLUE}Copiando para $INSTALL_DIR...${NC}"
rsync -a --delete --exclude='node_modules' --exclude='docker/.env' \
  "$SAFE_SOURCE/" "$INSTALL_DIR/"

cd "$INSTALL_DIR/docker"
chmod +x ./*.sh 2>/dev/null || true
chmod +x volumes/db/init/*.sh 2>/dev/null || true
echo -e "   ${GREEN}OK: Projeto copiado${NC}"

# ==============================================================
# ETAPA 6 - Configuracao .env
# ==============================================================
echo -e "\n${BLUE}==== Configuracao de Variaveis ====${NC}"
[ ! -f .env ] && cp .env.example .env

echo -e "${BLUE}Gerando credenciais automaticas...${NC}"
CURRENT_JWT=$(read_env "JWT_SECRET")
if [ -z "$CURRENT_JWT" ] || [ "$CURRENT_JWT" = "super-secret-jwt-token-with-at-least-32-characters-long" ]; then
  set_env "JWT_SECRET" "$(openssl rand -base64 32)"
  echo -e "   ${GREEN}OK: JWT_SECRET gerado${NC}"
fi

CURRENT_PG=$(read_env "POSTGRES_PASSWORD")
if [ -z "$CURRENT_PG" ] || [ "$CURRENT_PG" = "SuaSenhaForteAqui123!" ]; then
  set_env "POSTGRES_PASSWORD" "$(openssl rand -base64 24 | tr -d '=/+')"
  echo -e "   ${GREEN}OK: POSTGRES_PASSWORD gerado${NC}"
fi
[ -z "$(read_env "POSTGRES_USER")" ] && set_env "POSTGRES_USER" "supabase_admin"

CURRENT_ANON=$(read_env "ANON_KEY")
if [ -z "$CURRENT_ANON" ] || [ "$CURRENT_ANON" = "CHANGE_ME" ]; then
  JWT_SECRET=$(read_env "JWT_SECRET")
  ANON=$(gen_jwt "anon" "$JWT_SECRET")
  SERVICE=$(gen_jwt "service_role" "$JWT_SECRET")
  if [ -z "$ANON" ] || [ -z "$SERVICE" ]; then
    echo -e "${RED}Erro: Falha ao gerar JWT${NC}"
    exit 1
  fi
  set_env "ANON_KEY" "$ANON"
  set_env "SERVICE_ROLE_KEY" "$SERVICE"
  echo -e "   ${GREEN}OK: ANON_KEY + SERVICE_ROLE_KEY gerados${NC}"
fi

echo -e "\n${CYAN}=== Configuracoes do Site ===${NC}"
prompt_config "SITE_DOMAIN" "Dominio do site (ex: simplyimoveis.com.br)" "simplyimoveis.com.br" "false" "true"

echo -e "\n${CYAN}=== SMTP ===${NC}"
prompt_config "SMTP_HOST" "Servidor SMTP" "smtp.gmail.com"
prompt_config "SMTP_PORT" "Porta SMTP" "587"
prompt_config "SMTP_USER" "Email SMTP"
prompt_config "SMTP_PASS" "Senha SMTP - App Password" "" "true"
prompt_config "SMTP_SENDER_NAME" "Nome do remetente" "Simply Imoveis"
prompt_config "SMTP_ADMIN_EMAIL" "Email do admin" "admin@simplyimoveis.com.br"

echo -e "\n${CYAN}=== Integracoes ===${NC}"
prompt_config "GROQ_API_KEY" "Chave Groq API - chat IA" "" "true"

echo -e "\n${CYAN}=== Telegram - opcional ===${NC}"
prompt_config "TELEGRAM_BOT_TOKEN" "Telegram Bot Token"
prompt_config "TELEGRAM_CHAT_ID" "Telegram Chat ID"

echo -e "\n${CYAN}=== Credenciais Admin ===${NC}"
default_admin="$(read_env "SMTP_ADMIN_EMAIL")"
default_admin="${default_admin:-admin@simplyimoveis.com.br}"
read -p "Email admin [$default_admin]: " ADMIN_EMAIL
ADMIN_EMAIL="${ADMIN_EMAIL:-$default_admin}"
while [[ ! "$ADMIN_EMAIL" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; do
  read -p "   Email invalido, tente novamente: " ADMIN_EMAIL
done
while true; do
  read -s -p "Senha admin (min 8 caracteres): " ADMIN_PASS
  echo ""
  [ ${#ADMIN_PASS} -ge 8 ] && break
  echo -e "${YELLOW}Senha muito curta${NC}"
done

echo -e "\n${BLUE}Validando variaveis obrigatorias...${NC}"
MISSING=""
for var in SITE_DOMAIN JWT_SECRET POSTGRES_PASSWORD ANON_KEY SERVICE_ROLE_KEY; do
  val=$(read_env "$var")
  if [ -z "$val" ] || [ "$val" = "CHANGE_ME" ]; then
    MISSING="$MISSING $var"
  fi
done
if [ -n "$MISSING" ]; then
  echo -e "${RED}Erro: Variaveis faltando:$MISSING${NC}"
  exit 1
fi
echo -e "   ${GREEN}OK: Variaveis OK${NC}"

# ==============================================================
# ETAPA 7 - Kong + Edge Functions
# ==============================================================
echo -e "\n${BLUE}Preparando Kong + Functions...${NC}"
bash render-kong-config.sh
bash sync-functions.sh "$INSTALL_DIR/supabase/functions" "volumes/functions"
echo -e "   ${GREEN}OK: Kong + Functions prontos${NC}"

# ==============================================================
# ETAPA 8 - Subir DB e aguardar readiness
# ==============================================================
echo -e "\n${BLUE}Subindo PostgreSQL...${NC}"
docker compose up -d --build db
DB_USER=$(read_env "POSTGRES_USER")
DB_USER="${DB_USER:-supabase_admin}"
DB_NAME=$(read_env "POSTGRES_DB")
DB_NAME="${DB_NAME:-simply_db}"
for i in $(seq 1 90); do
  docker exec simply-db pg_isready -U "$DB_USER" -d "$DB_NAME" -q 2>/dev/null && break
  if [ "$i" = "90" ]; then
    echo -e "${RED}Erro: PostgreSQL nao respondeu em 180s${NC}"
    exit 1
  fi
  sleep 2
done
echo -e "   ${GREEN}OK: PostgreSQL pronto${NC}"

# ==============================================================
# ETAPA 9 - Bootstrap DB + Storage
# ==============================================================
echo -e "${BLUE}Bootstrap do banco e storage...${NC}"
if ! bash bootstrap-db.sh; then
  echo -e "${RED}Erro: Falha no bootstrap do banco/storage${NC}"
  echo -e "${YELLOW}Debug: docker compose logs --tail=120 db rest storage${NC}"
  exit 1
fi
echo -e "   ${GREEN}OK: Bootstrap concluido${NC}"

# ==============================================================
# ETAPA 10 - Subir todos os servicos
# ==============================================================
echo -e "\n${BLUE}Subindo todos os servicos...${NC}"
docker compose up -d --build --remove-orphans
echo -e "${BLUE}Aguardando servicos - 25s...${NC}"
sleep 25

# ==============================================================
# ETAPA 11 - Validacao
# ==============================================================
echo -e "\n${BLUE}Validando stack interno...${NC}"
if ! bash validate-install.sh; then
  echo -e "${YELLOW}Reiniciando servicos e tentando novamente...${NC}"
  docker compose restart auth rest storage kong functions
  sleep 20
  if ! bash validate-install.sh; then
    echo -e "${RED}Erro: Validacao do stack interno falhou. Debug: docker compose logs --tail=50${NC}"
    exit 1
  fi
fi

# ==============================================================
# ETAPA 12 - Criar admin
# ==============================================================
echo -e "\n${BLUE}Criando admin...${NC}"
bash create-admin.sh "$ADMIN_EMAIL" "$ADMIN_PASS"

# ==============================================================
# ETAPA 13 - SSL
# ==============================================================
SITE_DOMAIN=$(read_env "SITE_DOMAIN")
FRONTEND_PORT=$(read_env "FRONTEND_PORT")
FRONTEND_PORT="${FRONTEND_PORT:-3000}"
KONG_PORT=$(read_env "KONG_HTTP_PORT")
KONG_PORT="${KONG_PORT:-8000}"

if [ "$SKIP_SSL" != "true" ]; then
  echo ""
  read -p "Configurar SSL - Nginx + Lets Encrypt? (s/N): " DO_SSL
  if [[ "$DO_SSL" =~ ^[sS]$ ]]; then
    bash setup-ssl.sh
  else
    echo -e "${YELLOW}SSL nao configurado. Rode: sudo bash setup-ssl.sh${NC}"
  fi
else
  echo -e "${YELLOW}SSL pulado. Rode depois: sudo bash setup-ssl.sh${NC}"
fi

# ==============================================================
# RESULTADO FINAL
# ==============================================================
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Stack interno instalado com sucesso!${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}  Endpoints INTERNOS (já funcionando):${NC}"
echo -e "${GREEN}    Frontend:  http://127.0.0.1:${FRONTEND_PORT}${NC}"
echo -e "${GREEN}    API:       http://127.0.0.1:${KONG_PORT}${NC}"
echo -e "${GREEN}    Admin:     http://127.0.0.1:${FRONTEND_PORT}/admin${NC}"
echo -e "${GREEN}    Banco:     127.0.0.1:5432${NC}"
echo ""
echo -e "${CYAN}  Login admin:${NC}"
echo -e "${GREEN}    ${ADMIN_EMAIL}${NC}"
echo ""
echo -e "${YELLOW}══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  PUBLICAÇÃO EM DOMÍNIO (passo adicional):${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  O stack está rodando em 127.0.0.1.${NC}"
echo -e "${YELLOW}  Para expor via https://${SITE_DOMAIN}:${NC}"
echo -e "${YELLOW}    1. Configure o nginx do host:${NC}"
echo -e "${YELLOW}       sudo bash setup-ssl.sh${NC}"
echo -e "${YELLOW}       (ou copie nginx-site.conf manualmente)${NC}"
echo -e "${YELLOW}    2. Valide a exposição pública:${NC}"
echo -e "${YELLOW}       bash validate-install.sh --public${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}  Comandos úteis:${NC}"
echo -e "${GREEN}    bash status.sh               - status dos containers${NC}"
echo -e "${GREEN}    bash logs.sh                  - ver logs${NC}"
echo -e "${GREEN}    bash backup.sh                - backup do banco${NC}"
echo -e "${GREEN}    bash validate-install.sh        - validar stack interno${NC}"
echo -e "${GREEN}    bash validate-install.sh --public - validar URL pública${NC}"
echo ""
echo -e "${YELLOW}Altere a senha do admin no primeiro acesso!${NC}"
