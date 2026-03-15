#!/bin/bash
# ============================================================
# Simply Imóveis - Instalador Completo Docker
# Versão: 2026-03-15-v3-definitivo
# Uso: sudo bash install.sh
# ============================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║     Simply Imóveis - Instalador Docker v3           ║"
echo "║     Ubuntu 24.04 + Supabase Self-hosted + SSL       ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

[ "$EUID" -ne 0 ] && echo -e "${RED}❌ Execute com sudo: sudo bash install.sh${NC}" && exit 1

# ── Dependências do sistema ──────────────────────────────────
echo -e "${BLUE}📦 Instalando dependências do sistema...${NC}"
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq rsync curl openssl jq nginx certbot python3-certbot-nginx >/dev/null 2>&1

if ! command -v docker &>/dev/null; then
  echo -e "${YELLOW}⚠️  Docker não encontrado. Instalando...${NC}"
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker && systemctl start docker
fi

docker compose version &>/dev/null || apt-get install -y -qq docker-compose-plugin >/dev/null 2>&1

# ── Diretórios ───────────────────────────────────────────────
INSTALL_DIR="/opt/simply-imoveis"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

mkdir -p "$INSTALL_DIR"
echo -e "${BLUE}📋 Copiando arquivos do projeto...${NC}"
rsync -av --delete --exclude='node_modules' --exclude='.git' --exclude='docker/.env' "$PROJECT_DIR/" "$INSTALL_DIR/"
cd "$INSTALL_DIR/docker"
chmod +x *.sh

# ── Helper: ler .env sem source ──────────────────────────────
read_env_var() {
  grep -E "^${1}=" .env 2>/dev/null | head -1 | sed "s/^${1}=//" | tr -d '"' | tr -d "'"
}

set_env_var() {
  local key="$1" val="$2"
  local escaped_val
  escaped_val=$(printf '%s' "$val" | sed 's/[\/&]/\\&/g')
  if grep -qE "^${key}=" .env 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=\"${escaped_val}\"|" .env
  else
    echo "${key}=\"${escaped_val}\"" >> .env
  fi
}

prompt_config() {
  local var_name="$1" description="$2" default_val="${3:-}" is_secret="${4:-false}"
  local current_val
  current_val=$(read_env_var "$var_name")

  if [ -z "$current_val" ] || [ "$current_val" = "CHANGE_ME" ] || [ "$current_val" = "gsk_XXXXXXXXXXXXXXXXXXXX" ] || [ "$current_val" = "seu-email@gmail.com" ] || [ "$current_val" = "sua-senha-de-app" ]; then
    echo ""
    echo -e "${CYAN}📝 ${description}${NC}"
    [ -n "$default_val" ] && echo -e "   Padrão: ${default_val}"
    if [ "$is_secret" = "true" ]; then
      read -s -p "   > " input_val; echo ""
    else
      read -p "   > " input_val
    fi
    input_val="${input_val:-$default_val}"
    [ -n "$input_val" ] && set_env_var "$var_name" "$input_val"
  fi
}

# ── Criar .env se não existir ────────────────────────────────
if [ ! -f .env ]; then
  echo -e "${YELLOW}📝 Criando .env a partir do template...${NC}"
  cp .env.example .env
  JWT_SECRET=$(openssl rand -base64 32)
  PG_PASS=$(openssl rand -base64 24 | tr -d '=/+')
  sed -i "s|super-secret-jwt-token-with-at-least-32-characters-long|${JWT_SECRET}|g" .env
  sed -i "s|SuaSenhaForteAqui123!|${PG_PASS}|g" .env
fi

# ── Configuração interativa ──────────────────────────────────
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       Configuração Interativa                       ║${NC}"
echo -e "${BLUE}║  (ENTER mantém o valor atual/padrão)                ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"

prompt_config "SITE_DOMAIN" "Domínio do site (ex: simplyimoveis.com.br)" "simplyimoveis.com.br"
prompt_config "SMTP_HOST" "Servidor SMTP" "smtp.gmail.com"
prompt_config "SMTP_PORT" "Porta SMTP" "587"
prompt_config "SMTP_USER" "Email SMTP (remetente)"
prompt_config "SMTP_PASS" "Senha SMTP (App Password)" "" "true"
prompt_config "SMTP_SENDER_NAME" "Nome do remetente" "Simply Imóveis"
prompt_config "SMTP_ADMIN_EMAIL" "Email do administrador" "admin@simplyimoveis.com.br"
prompt_config "GROQ_API_KEY" "Chave API do Groq (chat IA Luma)" "" "true"
prompt_config "TELEGRAM_API_KEY" "Telegram API Key (opcional, via connector)" "" "true"
prompt_config "TELEGRAM_BOT_TOKEN" "Telegram Bot Token (opção direta, sem connector)" "" "true"
prompt_config "TELEGRAM_CHAT_ID" "Telegram Chat ID" ""

# ── Gerar chaves JWT se necessário ───────────────────────────
CURRENT_ANON=$(read_env_var "ANON_KEY")
if [ -z "$CURRENT_ANON" ] || [ "$CURRENT_ANON" = "CHANGE_ME" ]; then
  echo -e "${BLUE}🔑 Gerando ANON_KEY e SERVICE_ROLE_KEY...${NC}"
  bash generate-keys.sh
fi

# ── Renderizar kong.yml ──────────────────────────────────────
echo -e "${BLUE}🔧 Renderizando config do Kong...${NC}"
bash render-kong-config.sh

# ── Edge Functions ───────────────────────────────────────────
echo -e "${BLUE}📦 Preparando Edge Functions...${NC}"
mkdir -p volumes/functions/{main,chat,notify-telegram,create-admin-user}
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

# ── Subir banco ──────────────────────────────────────────────
echo -e "${BLUE}🔨 Subindo banco de dados...${NC}"
docker compose up -d --build db

for _ in {1..40}; do
  DB_HEALTH=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' simply-db 2>/dev/null || true)
  [ "$DB_HEALTH" = "healthy" ] && break
  sleep 2
done

if [ "$DB_HEALTH" != "healthy" ]; then
  echo -e "${RED}❌ Banco não ficou saudável.${NC}"
  docker compose logs --tail=30 db
  exit 1
fi

# ── Sincronizar credenciais e permissões ─────────────────────
echo -e "${BLUE}🔐 Sincronizando credenciais e permissões...${NC}"
bash sync-db-passwords.sh --quiet

# ── Subir stack completa ─────────────────────────────────────
echo -e "${BLUE}🚀 Subindo stack completa...${NC}"
docker compose up -d --build --force-recreate auth rest storage functions kong frontend --remove-orphans

echo -e "${BLUE}⏳ Aguardando serviços estabilizarem (20s)...${NC}"
sleep 20

# ── Re-sync após GoTrue criar tabelas no schema auth ────────
echo -e "${BLUE}🔐 Re-sincronizando permissões (pós-migração GoTrue)...${NC}"
bash sync-db-passwords.sh --quiet

# ── Restart auth para pegar permissões atualizadas ───────────
echo -e "${BLUE}🔄 Reiniciando auth com permissões corretas...${NC}"
docker compose restart auth
sleep 10

# ── Validação ────────────────────────────────────────────────
echo -e "${BLUE}🧪 Validando instalação...${NC}"
if ! bash validate-install.sh; then
  echo -e "${YELLOW}⚠️  Validação com problemas. Tentando re-sync e restart...${NC}"
  bash sync-db-passwords.sh --quiet
  docker compose up -d --force-recreate auth kong
  sleep 15
  if ! bash validate-install.sh; then
    echo -e "${RED}❌ Validação falhou. Veja: docker compose logs --tail=80 auth kong${NC}"
    exit 1
  fi
fi

# ── Criar admin padrão ───────────────────────────────────────
echo -e "${BLUE}👤 Criando usuário admin padrão...${NC}"
bash create-admin.sh "tmunizs89@proton.me" "10203040"

# ── SSL ──────────────────────────────────────────────────────
SITE_DOMAIN=$(read_env_var "SITE_DOMAIN")
ADMIN_EMAIL=$(read_env_var "SMTP_ADMIN_EMAIL")
FRONTEND_PORT=$(read_env_var "FRONTEND_PORT")
KONG_PORT=$(read_env_var "KONG_HTTP_PORT")
FRONTEND_PORT="${FRONTEND_PORT:-3000}"
KONG_PORT="${KONG_PORT:-8000}"

echo ""
read -p "Deseja configurar SSL (Nginx + Let's Encrypt) agora? (s/N): " INSTALL_SSL
if [[ "$INSTALL_SSL" =~ ^[sS]$ ]]; then
  echo -e "${BLUE}🔐 Configurando Nginx + SSL...${NC}"

  systemctl enable nginx >/dev/null 2>&1 || true
  systemctl start nginx >/dev/null 2>&1 || true

  NGINX_CONF="/etc/nginx/sites-available/simplyimoveis.conf"
  cat > "$NGINX_CONF" <<NGINXEOF
server {
    listen 80;
    server_name ${SITE_DOMAIN} www.${SITE_DOMAIN};
    client_max_body_size 50M;

    location / {
        proxy_pass http://127.0.0.1:${FRONTEND_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:${KONG_PORT}/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 300s;
    }
}
NGINXEOF

  rm -f /etc/nginx/sites-enabled/default
  ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/simplyimoveis.conf
  nginx -t && systemctl reload nginx

  if [ -z "$ADMIN_EMAIL" ]; then
    read -p "Email para avisos SSL: " ADMIN_EMAIL
  fi

  echo -e "${BLUE}🔐 Emitindo certificado SSL...${NC}"
  if certbot --nginx --non-interactive --agree-tos --email "${ADMIN_EMAIL:-admin@${SITE_DOMAIN}}" \
    -d "$SITE_DOMAIN" -d "www.$SITE_DOMAIN" --redirect; then
    echo -e "${GREEN}✅ SSL configurado!${NC}"
    certbot renew --dry-run || true
  else
    echo -e "${YELLOW}⚠️  SSL falhou. Verifique DNS e tente: sudo certbot --nginx -d ${SITE_DOMAIN}${NC}"
  fi
fi

# ── Resultado final ──────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        ✅ Instalação concluída com sucesso!          ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  Frontend: http://localhost:${FRONTEND_PORT}                     ║${NC}"
echo -e "${GREEN}║  API:      http://localhost:${KONG_PORT}                     ║${NC}"
echo -e "${GREEN}║  Admin:    https://${SITE_DOMAIN}/admin              ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  Login:    tmunizs89@proton.me / 10203040           ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}⚠️  Altere a senha do admin no primeiro acesso!${NC}"