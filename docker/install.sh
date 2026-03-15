#!/bin/bash
# ============================================================
# Simply Imóveis - Instalador Completo Docker
# Versão: 2026-03-15-v5-rewrite
# Uso: sudo bash install.sh
# ============================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║     Simply Imóveis - Instalador Docker v5           ║"
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

  # Pula se já tem valor válido
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
  set_env "JWT_SECRET" "$(openssl rand -base64 32)"
  set_env "POSTGRES_PASSWORD" "$(openssl rand -base64 24 | tr -d '=/+')"
fi

# ── 5. Configuração interativa ───────────────────────────────
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

# ── 6. Gerar JWT keys ───────────────────────────────────────
CURRENT_ANON=$(read_env "ANON_KEY")
if [ -z "$CURRENT_ANON" ] || [ "$CURRENT_ANON" = "CHANGE_ME" ]; then
  echo -e "${BLUE}🔑 Gerando chaves JWT...${NC}"
  bash generate-keys.sh
fi

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

# ── 9. Subir banco e sincronizar ─────────────────────────────
echo -e "${BLUE}🔨 Subindo banco...${NC}"
docker compose up -d --build db

for _ in {1..40}; do
  docker compose exec -T db pg_isready -U postgres -q 2>/dev/null && break
  sleep 2
done

echo -e "${BLUE}🔐 Sincronizando credenciais...${NC}"
bash sync-db-passwords.sh

# ── 10. Subir stack completa ─────────────────────────────────
echo -e "${BLUE}🚀 Subindo stack...${NC}"
docker compose up -d --build --force-recreate auth rest storage functions kong frontend --remove-orphans

echo -e "${BLUE}⏳ Aguardando GoTrue migrar (25s)...${NC}"
sleep 25

# Re-sync após GoTrue criar tabelas
echo -e "${BLUE}🔐 Re-sincronizando permissões...${NC}"
bash sync-db-passwords.sh

# Restart auth para pegar permissões
docker compose restart auth
sleep 10

# ── 11. Validação ────────────────────────────────────────────
echo -e "${BLUE}🧪 Validando...${NC}"
if ! bash validate-install.sh; then
  echo -e "${YELLOW}⚠️  Tentando re-sync + restart...${NC}"
  bash sync-db-passwords.sh
  docker compose up -d --force-recreate auth kong
  sleep 15
  bash validate-install.sh || { echo -e "${RED}❌ Validação falhou. Logs: docker compose logs --tail=50 auth kong${NC}"; exit 1; }
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
