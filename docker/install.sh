#!/bin/bash
# ============================================================
# Simply Imóveis - Instalador Completo Docker
# Versão: 2026-03-15-v10-definitive
# Uso: sudo bash install.sh
# ============================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║     Simply Imóveis - Instalador Docker v10          ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

[ "$EUID" -ne 0 ] && echo -e "${RED}❌ Execute com sudo${NC}" && exit 1

# ── 1. Dependências ──────────────────────────────────────────
echo -e "${BLUE}📦 Dependências do sistema...${NC}"
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq rsync curl openssl jq nginx certbot python3-certbot-nginx >/dev/null 2>&1

if ! command -v docker &>/dev/null; then
  echo -e "${YELLOW}⚠️  Instalando Docker...${NC}"
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker && systemctl start docker
fi
docker compose version &>/dev/null || apt-get install -y -qq docker-compose-plugin >/dev/null 2>&1

# ── 2. Diretórios ────────────────────────────────────────────
INSTALL_DIR="/opt/simply-imoveis"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

mkdir -p "$INSTALL_DIR"
echo -e "${BLUE}📋 Copiando projeto...${NC}"
rsync -av --delete --exclude='node_modules' --exclude='.git' --exclude='docker/.env' "$PROJECT_DIR/" "$INSTALL_DIR/"
cd "$INSTALL_DIR/docker"
chmod +x *.sh
chmod +x volumes/db/init/*.sh 2>/dev/null || true

# ── 3. Helpers ───────────────────────────────────────────────
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

  echo ""
  echo -e "${CYAN}📝 ${desc}${NC}"
  [ -n "$default" ] && echo -e "   Padrão: ${default}"
  if [ "$secret" = "true" ]; then
    read -s -p "   > " val; echo ""
  else
    read -p "   > " val
  fi
  val="${val:-$default}"
  [ -n "$val" ] && set_env "$var" "$val"
}

# ── 4. Criar .env ────────────────────────────────────────────
if [ ! -f .env ]; then
  echo -e "${YELLOW}📝 Criando .env...${NC}"
  cp .env.example .env
fi

# ── 5. Auto-gerar senhas e chaves ────────────────────────────
echo -e "${BLUE}🔑 Verificando/gerando credenciais...${NC}"

CURRENT_JWT=$(read_env "JWT_SECRET")
if [ -z "$CURRENT_JWT" ] || [ "$CURRENT_JWT" = "super-secret-jwt-token-with-at-least-32-characters-long" ]; then
  NEW_JWT=$(openssl rand -base64 32)
  set_env "JWT_SECRET" "$NEW_JWT"
  echo -e "   ${GREEN}✅ JWT_SECRET gerado${NC}"
fi

CURRENT_PG=$(read_env "POSTGRES_PASSWORD")
if [ -z "$CURRENT_PG" ] || [ "$CURRENT_PG" = "SuaSenhaForteAqui123!" ]; then
  NEW_PG=$(openssl rand -base64 24 | tr -d '=/+')
  set_env "POSTGRES_PASSWORD" "$NEW_PG"
  echo -e "   ${GREEN}✅ POSTGRES_PASSWORD gerado${NC}"
fi

CURRENT_PG_USER=$(read_env "POSTGRES_USER")
if [ -z "$CURRENT_PG_USER" ]; then
  set_env "POSTGRES_USER" "supabase_admin"
  echo -e "   ${GREEN}✅ POSTGRES_USER definido (supabase_admin)${NC}"
fi

CURRENT_ANON=$(read_env "ANON_KEY")
if [ -z "$CURRENT_ANON" ] || [ "$CURRENT_ANON" = "CHANGE_ME" ]; then
  echo -e "   ${BLUE}🔑 Gerando ANON_KEY e SERVICE_ROLE_KEY...${NC}"
  JWT_SECRET=$(read_env "JWT_SECRET")

  generate_jwt() {
    local role="$1"
    local js_code="
      const crypto = require('crypto');
      const header = Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url');
      const payload = Buffer.from(JSON.stringify({ref:'simply',role:'${role}',iss:'supabase',iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+315360000})).toString('base64url');
      const sig = crypto.createHmac('sha256','${JWT_SECRET}').update(header+'.'+payload).digest('base64url');
      console.log(header+'.'+payload+'.'+sig);
    "
    if command -v node &> /dev/null; then
      node -e "$js_code"
    else
      docker run --rm node:20-alpine node -e "$js_code"
    fi
  }

  ANON=$(generate_jwt "anon")
  SERVICE=$(generate_jwt "service_role")

  if [ -z "$ANON" ] || [ -z "$SERVICE" ]; then
    echo -e "${RED}❌ Falha ao gerar chaves JWT${NC}"; exit 1
  fi

  set_env "ANON_KEY" "$ANON"
  set_env "SERVICE_ROLE_KEY" "$SERVICE"
  echo -e "   ${GREEN}✅ ANON_KEY e SERVICE_ROLE_KEY gerados${NC}"
fi

# ── 6. Configuração interativa ───────────────────────────────
echo ""
echo -e "${BLUE}════ Configuração (ENTER = manter atual) ════${NC}"

prompt_config "SITE_DOMAIN"      "Domínio do site" "simplyimoveis.com.br"
prompt_config "SMTP_HOST"        "Servidor SMTP" "smtp.gmail.com"
prompt_config "SMTP_PORT"        "Porta SMTP" "587"
prompt_config "SMTP_USER"        "Email SMTP (remetente)"
prompt_config "SMTP_PASS"        "Senha SMTP (App Password)" "" "true"
prompt_config "SMTP_SENDER_NAME" "Nome do remetente" "Simply Imóveis"
prompt_config "SMTP_ADMIN_EMAIL" "Email do administrador" "admin@simplyimoveis.com.br"
prompt_config "GROQ_API_KEY"     "Chave API do Groq (chat IA Luma)" "" "true"
prompt_config "TELEGRAM_BOT_TOKEN" "Telegram Bot Token (notificações, ENTER p/ pular)" ""
prompt_config "TELEGRAM_CHAT_ID"   "Telegram Chat ID" ""

# ── 7. Kong config ──────────────────────────────────────────
echo -e "${BLUE}🔧 Renderizando Kong config...${NC}"
bash render-kong-config.sh

# ── 8. Edge Functions ────────────────────────────────────────
echo -e "${BLUE}📦 Preparando Edge Functions...${NC}"
mkdir -p volumes/functions/{main,chat,notify-telegram,create-admin-user}
cp "$INSTALL_DIR/supabase/functions/chat/index.ts" volumes/functions/chat/index.ts 2>/dev/null || true
cp "$INSTALL_DIR/supabase/functions/notify-telegram/index.ts" volumes/functions/notify-telegram/index.ts 2>/dev/null || true
cp "$INSTALL_DIR/supabase/functions/create-admin-user/index.ts" volumes/functions/create-admin-user/index.ts 2>/dev/null || true

cat > volumes/functions/main/index.ts << 'MAINEOF'
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
serve(async (req) => {
  const url = new URL(req.url);
  const fn = url.pathname.split("/").filter(Boolean)[0];
  if (!fn) return new Response(JSON.stringify({ status: "ok" }), { headers: { "Content-Type": "application/json" } });
  try {
    const mod = await import(`../${fn}/index.ts`);
    return mod.default ? mod.default(req) : new Response("OK", { status: 200 });
  } catch {
    return new Response(JSON.stringify({ error: `Function '${fn}' not found` }), { status: 404, headers: { "Content-Type": "application/json" } });
  }
});
MAINEOF

# ── 9. Limpar instalação anterior ────────────────────────────
echo ""
EXISTING=$(docker compose ps -q 2>/dev/null | wc -l)
if [ "$EXISTING" -gt 0 ]; then
  echo -e "${YELLOW}⚠️  Instalação anterior detectada.${NC}"
  read -p "   Limpar tudo e reinstalar? (S/n): " CLEAN
  if [[ ! "$CLEAN" =~ ^[nN]$ ]]; then
    echo -e "${BLUE}🗑️  Removendo containers e volumes...${NC}"
    docker compose down -v --remove-orphans 2>/dev/null || true
  fi
fi

# ══════════════════════════════════════════════════════════════
# FASE 1: Subir APENAS o banco de dados
# ══════════════════════════════════════════════════════════════
echo ""
echo -e "${BLUE}🐘 FASE 1: Subindo apenas o banco de dados...${NC}"
docker compose up -d --build db

echo -e "${BLUE}⏳ Aguardando banco aceitar conexões...${NC}"
for i in {1..60}; do
  if docker exec simply-db pg_isready -U supabase_admin -q 2>/dev/null; then
    echo -e "   ${GREEN}✅ Banco aceitando conexões (tentativa $i)${NC}"
    break
  fi
  [ "$i" = "60" ] && echo -e "${RED}❌ Banco não respondeu em 120s${NC}" && docker logs --tail=30 simply-db && exit 1
  sleep 2
done

# Aguardar init scripts completarem (roles são criados pela imagem supabase/postgres)
echo -e "${BLUE}⏳ Aguardando init scripts e roles internos (15s)...${NC}"
sleep 15

# ══════════════════════════════════════════════════════════════
# FASE 2: Sincronizar senhas dos roles
# ══════════════════════════════════════════════════════════════
echo -e "${BLUE}🔐 FASE 2: Sincronizando senhas dos roles internos...${NC}"
if ! bash sync-db-passwords.sh; then
  echo -e "${RED}❌ Falha ao sincronizar credenciais${NC}"
  echo -e "${YELLOW}   Logs do banco:${NC}"
  docker logs --tail=40 simply-db
  exit 1
fi

# ══════════════════════════════════════════════════════════════
# FASE 3: Subir todos os serviços restantes
# ══════════════════════════════════════════════════════════════
echo ""
echo -e "${BLUE}🚀 FASE 3: Subindo serviços restantes...${NC}"
docker compose up -d --build --remove-orphans

echo -e "${BLUE}⏳ Aguardando serviços estabilizarem (25s)...${NC}"
sleep 25

# ── 11. Validação ────────────────────────────────────────────
echo -e "${BLUE}🧪 Validando...${NC}"
if ! bash validate-install.sh; then
  echo -e "${YELLOW}⚠️  Reiniciando auth e kong...${NC}"
  docker compose restart auth kong
  sleep 15
  bash validate-install.sh || {
    echo -e "${RED}❌ Validação falhou. Debug:${NC}"
    echo "   docker compose logs --tail=30 auth"
    echo "   docker compose logs --tail=30 kong"
    echo "   docker compose logs --tail=30 db"
    exit 1
  }
fi

# ── 12. Criar admin ─────────────────────────────────────────
echo -e "${BLUE}👤 Criando admin...${NC}"
bash create-admin.sh "tmunizs89@proton.me" "10203040"

# ── 13. SSL ──────────────────────────────────────────────────
SITE_DOMAIN=$(read_env "SITE_DOMAIN")
ADMIN_EMAIL=$(read_env "SMTP_ADMIN_EMAIL")
FRONTEND_PORT=$(read_env "FRONTEND_PORT"); FRONTEND_PORT="${FRONTEND_PORT:-3000}"
KONG_PORT=$(read_env "KONG_HTTP_PORT"); KONG_PORT="${KONG_PORT:-8000}"

echo ""
read -p "Configurar SSL (Nginx + Let's Encrypt)? (s/N): " DO_SSL
if [[ "$DO_SSL" =~ ^[sS]$ ]]; then
  echo -e "${BLUE}🔐 Configurando Nginx + SSL...${NC}"
  systemctl enable nginx >/dev/null 2>&1 || true
  systemctl start nginx >/dev/null 2>&1 || true

  cat > /etc/nginx/sites-available/simplyimoveis.conf <<NGINXEOF
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
        proxy_read_timeout 300s;
    }
}
NGINXEOF

  rm -f /etc/nginx/sites-enabled/default
  ln -sf /etc/nginx/sites-available/simplyimoveis.conf /etc/nginx/sites-enabled/
  nginx -t && systemctl reload nginx

  [ -z "$ADMIN_EMAIL" ] && read -p "Email para SSL: " ADMIN_EMAIL

  if certbot --nginx --non-interactive --agree-tos --email "${ADMIN_EMAIL:-admin@${SITE_DOMAIN}}" \
    -d "$SITE_DOMAIN" -d "www.$SITE_DOMAIN" --redirect; then
    echo -e "${GREEN}✅ SSL configurado!${NC}"
  else
    echo -e "${YELLOW}⚠️  SSL falhou. Tente: sudo certbot --nginx -d ${SITE_DOMAIN}${NC}"
  fi
fi

# ── Resultado ────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        ✅ Instalação concluída!                      ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  Frontend: http://localhost:${FRONTEND_PORT}                     ║${NC}"
echo -e "${GREEN}║  API:      http://localhost:${KONG_PORT}                     ║${NC}"
echo -e "${GREEN}║  Admin:    https://${SITE_DOMAIN}/admin              ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  Login:    tmunizs89@proton.me / 10203040           ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}⚠️  Altere a senha do admin no primeiro acesso!${NC}"