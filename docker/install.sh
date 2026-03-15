#!/bin/bash
set -euo pipefail

# ============================================================
# Simply Imóveis - Instalador Interativo Docker
# Uso: sudo bash install.sh
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║        Simply Imóveis - Instalador Docker           ║"
echo "║        Ubuntu 24.04 + Supabase Self-hosted          ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ---- Verificações ----
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}❌ Execute com sudo: sudo bash install.sh${NC}"
  exit 1
fi

if ! command -v docker &> /dev/null; then
  echo -e "${YELLOW}⚠️  Docker não encontrado. Instalando...${NC}"
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
  echo -e "${GREEN}✅ Docker instalado.${NC}"
fi

if ! docker compose version &> /dev/null; then
  echo -e "${YELLOW}⚠️  Docker Compose plugin não encontrado. Instalando...${NC}"
  apt-get update && apt-get install -y docker-compose-plugin
  echo -e "${GREEN}✅ Docker Compose instalado.${NC}"
fi

# ---- Diretório do projeto ----
INSTALL_DIR="/opt/simply-imoveis"
echo -e "${BLUE}📂 Diretório de instalação: ${INSTALL_DIR}${NC}"

if [ -d "$INSTALL_DIR" ]; then
  echo -e "${YELLOW}⚠️  Diretório já existe. Atualizando...${NC}"
else
  mkdir -p "$INSTALL_DIR"
fi

# Copia os arquivos do projeto
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}📋 Copiando arquivos do projeto...${NC}"
rsync -av --delete --exclude='node_modules' --exclude='.git' --exclude='docker/.env' "$PROJECT_DIR/" "$INSTALL_DIR/"

cd "$INSTALL_DIR/docker"
chmod +x *.sh

# ---- Função helper para ler variável do .env ----
read_env_var() {
  grep -E "^${1}=" .env 2>/dev/null | head -1 | sed "s/^${1}=//" | tr -d '"' | tr -d "'"
}

# ---- Prompt interativo para configurar .env ----
prompt_config() {
  local var_name="$1"
  local description="$2"
  local default_val="${3:-}"
  local is_secret="${4:-false}"
  local current_val

  current_val=$(read_env_var "$var_name")

  if [ -n "$current_val" ] && [ "$current_val" != "CHANGE_ME" ] && [ "$current_val" != "gsk_XXXXXXXXXXXXXXXXXXXX" ] && [ "$current_val" != "seu-email@gmail.com" ] && [ "$current_val" != "sua-senha-de-app" ]; then
    return 0
  fi

  echo ""
  echo -e "${CYAN}📝 ${description}${NC}"
  if [ -n "$default_val" ]; then
    echo -e "   Padrão: ${default_val}"
  fi

  if [ "$is_secret" = "true" ]; then
    read -s -p "   > " input_val
    echo ""
  else
    read -p "   > " input_val
  fi

  input_val="${input_val:-$default_val}"

  if [ -n "$input_val" ]; then
    # Escapa caracteres especiais para sed
    local escaped_val
    escaped_val=$(printf '%s\n' "$input_val" | sed 's/[&/\]/\\&/g')
    sed -i "s|^${var_name}=.*|${var_name}=\"${escaped_val}\"|" .env
  fi
}

# ---- Gerar .env se não existir ----
if [ ! -f .env ]; then
  echo -e "${YELLOW}📝 Criando arquivo de configuração...${NC}"
  cp .env.example .env

  # Gerar JWT_SECRET automaticamente
  JWT_SECRET=$(openssl rand -base64 32)
  sed -i "s|super-secret-jwt-token-with-at-least-32-characters-long|${JWT_SECRET}|g" .env

  # Gerar senha do banco automaticamente
  PG_PASS=$(openssl rand -base64 24 | tr -d '=/+')
  sed -i "s|SuaSenhaForteAqui123!|${PG_PASS}|g" .env

  echo -e "${GREEN}✅ JWT_SECRET e senha do banco gerados automaticamente.${NC}"
fi

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       Configuração Interativa                       ║${NC}"
echo -e "${BLUE}║  (pressione ENTER para manter o valor atual/padrão) ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"

prompt_config "SITE_DOMAIN" "Domínio do site (ex: simplyimoveis.com.br)" "simplyimoveis.com.br"
prompt_config "SMTP_HOST" "Servidor SMTP" "smtp.gmail.com"
prompt_config "SMTP_PORT" "Porta SMTP" "587"
prompt_config "SMTP_USER" "Email SMTP (remetente)"
prompt_config "SMTP_PASS" "Senha SMTP (App Password do Gmail)" "" "true"
prompt_config "SMTP_SENDER_NAME" "Nome do remetente de emails" "Simply Imóveis"
prompt_config "SMTP_ADMIN_EMAIL" "Email do administrador" "admin@simplyimoveis.com.br"
prompt_config "GROQ_API_KEY" "Chave API do Groq (para chat IA)" "" "true"
prompt_config "TELEGRAM_BOT_TOKEN" "Token do Bot Telegram (opcional, ENTER para pular)" ""
prompt_config "TELEGRAM_CHAT_ID" "Chat ID do Telegram (opcional, ENTER para pular)" ""

echo ""
echo -e "${GREEN}✅ Configuração salva!${NC}"

# ---- Garantir ANON_KEY/SERVICE_ROLE_KEY válidas ----
CURRENT_ANON=$(read_env_var "ANON_KEY")
if [ -z "$CURRENT_ANON" ] || [ "$CURRENT_ANON" = "CHANGE_ME" ]; then
  echo -e "${BLUE}🔑 Gerando ANON_KEY e SERVICE_ROLE_KEY...${NC}"
  bash generate-keys.sh
fi

# ---- Copiar Edge Functions ----
echo -e "${BLUE}📦 Preparando Edge Functions...${NC}"
mkdir -p volumes/functions/main
mkdir -p volumes/functions/chat
mkdir -p volumes/functions/notify-telegram
mkdir -p volumes/functions/create-admin-user

cp "$INSTALL_DIR/supabase/functions/chat/index.ts" volumes/functions/chat/index.ts 2>/dev/null || true
cp "$INSTALL_DIR/supabase/functions/notify-telegram/index.ts" volumes/functions/notify-telegram/index.ts 2>/dev/null || true
cp "$INSTALL_DIR/supabase/functions/create-admin-user/index.ts" volumes/functions/create-admin-user/index.ts 2>/dev/null || true

cat > volumes/functions/main/index.ts << 'MAINEOF'
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

serve(async (req) => {
  const url = new URL(req.url);
  const path = url.pathname.split("/").filter(Boolean);
  const functionName = path[0];

  if (!functionName) {
    return new Response(JSON.stringify({ status: "ok" }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const mod = await import(`../${functionName}/index.ts`);
    return mod.default ? mod.default(req) : new Response("Function loaded", { status: 200 });
  } catch {
    return new Response(JSON.stringify({ error: `Function '${functionName}' not found` }), {
      status: 404,
      headers: { "Content-Type": "application/json" },
    });
  }
});
MAINEOF

# ---- Build e Start ----
echo ""
echo -e "${BLUE}🔨 Subindo banco de dados...${NC}"
docker compose up -d --build db

echo -e "${BLUE}⏳ Aguardando banco ficar saudável...${NC}"
for i in $(seq 1 30); do
  DB_HEALTH=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' simply-db 2>/dev/null || true)
  if [ "$DB_HEALTH" = "healthy" ]; then
    echo -e "${GREEN}✅ Banco saudável.${NC}"
    break
  fi
  sleep 2
done

if [ "$DB_HEALTH" != "healthy" ]; then
  echo -e "${RED}❌ Banco não ficou saudável a tempo.${NC}"
  docker compose logs --tail=30 db
  exit 1
fi

echo -e "${BLUE}🔧 Sincronizando credenciais internas do banco...${NC}"
bash sync-db-passwords.sh --quiet

echo -e "${BLUE}🚀 Subindo serviços...${NC}"
docker compose up -d --build --force-recreate auth rest storage functions kong frontend --remove-orphans

echo -e "${BLUE}⏳ Aguardando serviços estabilizarem (20s)...${NC}"
sleep 20

echo -e "${BLUE}🧪 Validando instalação...${NC}"
bash validate-install.sh || true

# ---- Pergunta se quer criar admin ----
echo ""
echo -e "${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  👤 Criar usuário administrador?                     ║${NC}"
echo -e "${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
read -p "Deseja criar o admin agora? (s/N): " CREATE_ADMIN

if [ "$CREATE_ADMIN" = "s" ] || [ "$CREATE_ADMIN" = "S" ]; then
  read -p "Email do admin: " ADMIN_EMAIL
  read -s -p "Senha do admin: " ADMIN_PASS
  echo ""

  if [ -n "$ADMIN_EMAIL" ] && [ -n "$ADMIN_PASS" ]; then
    bash create-admin.sh "$ADMIN_EMAIL" "$ADMIN_PASS"
  else
    echo -e "${RED}❌ Email e senha são obrigatórios.${NC}"
  fi
fi

SITE_DOMAIN=$(read_env_var "SITE_DOMAIN")

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        ✅ Simply Imóveis instalado com sucesso!      ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║                                                      ║${NC}"
echo -e "${GREEN}║  Frontend:  http://localhost:3000                    ║${NC}"
echo -e "${GREEN}║  API:       http://localhost:8000                    ║${NC}"
echo -e "${GREEN}║                                                      ║${NC}"
echo -e "${GREEN}║  Próximos passos:                                    ║${NC}"
echo -e "${GREEN}║  1. Configure o Nginx (veja nginx-site.conf)         ║${NC}"
echo -e "${GREEN}║  2. Instale SSL:                                     ║${NC}"
echo -e "${GREEN}║     certbot --nginx -d ${SITE_DOMAIN:-seudominio}    ║${NC}"
echo -e "${GREEN}║  3. Se não criou admin, rode:                        ║${NC}"
echo -e "${GREEN}║     bash create-admin.sh email@ex.com senha          ║${NC}"
echo -e "${GREEN}║                                                      ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
