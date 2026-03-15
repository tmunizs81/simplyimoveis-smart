#!/bin/bash
set -euo pipefail

# ============================================================
#  Simply Imóveis - Instalador Completo de Produção
#  VPS Ubuntu 24.04 + Docker + Nginx + SSL + Supabase Self-hosted
#
#  Uso: curl -sSL <url> | sudo bash
#  Ou:  sudo bash deploy.sh
#
#  GitHub: https://github.com/tmunizs81/simplyimoveis-smart
# ============================================================

# ---- Cores ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ---- Config ----
REPO_URL="https://github.com/tmunizs81/simplyimoveis-smart.git"
INSTALL_DIR="/opt/simply-imoveis"
BACKUP_DIR="/opt/simply-imoveis/backups"
DOMAIN="simplyimoveis.com.br"
ADMIN_EMAIL=""
ADMIN_PASS=""
GROQ_KEY=""

# ---- Banner ----
banner() {
  echo -e "${CYAN}"
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║                                                          ║"
  echo "║    ███████╗██╗███╗   ███╗██████╗ ██╗  ██╗   ██╗          ║"
  echo "║    ██╔════╝██║████╗ ████║██╔══██╗██║  ╚██╗ ██╔╝          ║"
  echo "║    ███████╗██║██╔████╔██║██████╔╝██║   ╚████╔╝           ║"
  echo "║    ╚════██║██║██║╚██╔╝██║██╔═══╝ ██║    ╚██╔╝            ║"
  echo "║    ███████║██║██║ ╚═╝ ██║██║     ███████╗██║             ║"
  echo "║    ╚══════╝╚═╝╚═╝     ╚═╝╚═╝     ╚══════╝╚═╝             ║"
  echo "║                                                          ║"
  echo "║          INSTALADOR DE PRODUÇÃO v2.0                     ║"
  echo "║          Ubuntu 24.04 + Docker + Supabase                ║"
  echo "║                                                          ║"
  echo "╚══════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✅]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[⚠️]${NC} $1"; }
log_error()   { echo -e "${RED}[❌]${NC} $1"; }
log_step()    { echo -e "\n${BOLD}${CYAN}━━━ $1 ━━━${NC}\n"; }

# ---- Verificação root ----
check_root() {
  if [ "$EUID" -ne 0 ]; then
    log_error "Execute com sudo: sudo bash deploy.sh"
    exit 1
  fi
}

# ---- Coleta de dados ----
collect_info() {
  log_step "CONFIGURAÇÃO INICIAL"

  # Domínio
  read -p "$(echo -e "${BOLD}Domínio do sistema${NC} [${DOMAIN}]: ")" input_domain
  DOMAIN="${input_domain:-$DOMAIN}"

  # Admin
  echo ""
  read -p "$(echo -e "${BOLD}Email do administrador${NC}: ")" ADMIN_EMAIL
  while [ -z "$ADMIN_EMAIL" ]; do
    log_warn "Email é obrigatório"
    read -p "$(echo -e "${BOLD}Email do administrador${NC}: ")" ADMIN_EMAIL
  done

  read -sp "$(echo -e "${BOLD}Senha do administrador${NC} (mín. 8 chars): ")" ADMIN_PASS
  echo ""
  while [ ${#ADMIN_PASS} -lt 8 ]; do
    log_warn "Senha deve ter pelo menos 8 caracteres"
    read -sp "$(echo -e "${BOLD}Senha do administrador${NC}: ")" ADMIN_PASS
    echo ""
  done

  # GROQ
  echo ""
  read -p "$(echo -e "${BOLD}GROQ API Key${NC} (para chat IA): ")" GROQ_KEY
  while [ -z "$GROQ_KEY" ]; do
    log_warn "GROQ API Key é obrigatória para o chat funcionar"
    log_info "Obtenha em: https://console.groq.com/keys"
    read -p "$(echo -e "${BOLD}GROQ API Key${NC}: ")" GROQ_KEY
  done

  # Telegram (opcional)
  echo ""
  read -p "$(echo -e "${BOLD}Telegram Bot Token${NC} (opcional, ENTER para pular): ")" TELEGRAM_BOT_TOKEN
  TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
  
  TELEGRAM_CHAT_ID=""
  if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
    read -p "$(echo -e "${BOLD}Telegram Chat ID${NC}: ")" TELEGRAM_CHAT_ID
  fi

  echo ""
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  Domínio:       ${BOLD}${DOMAIN}${NC}"
  echo -e "  Admin:         ${BOLD}${ADMIN_EMAIL}${NC}"
  echo -e "  GROQ Key:      ${BOLD}${GROQ_KEY:0:10}...${NC}"
  echo -e "  Telegram:      ${BOLD}${TELEGRAM_BOT_TOKEN:+Configurado}${TELEGRAM_BOT_TOKEN:-Não configurado}${NC}"
  echo -e "  Diretório:     ${BOLD}${INSTALL_DIR}${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  read -p "$(echo -e "${BOLD}Confirma? (s/N)${NC}: ")" confirm
  if [[ ! "$confirm" =~ ^[sS]$ ]]; then
    log_error "Instalação cancelada."
    exit 0
  fi
}

# ---- Instalar dependências do sistema ----
install_system_deps() {
  log_step "PASSO 1/8 — Instalando dependências do sistema"

  apt-get update -qq

  # Docker
  if ! command -v docker &> /dev/null; then
    log_info "Instalando Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    log_success "Docker instalado"
  else
    log_success "Docker já instalado ($(docker --version | cut -d' ' -f3))"
  fi

  # Docker Compose
  if ! docker compose version &> /dev/null 2>&1; then
    log_info "Instalando Docker Compose plugin..."
    apt-get install -y -qq docker-compose-plugin
    log_success "Docker Compose instalado"
  else
    log_success "Docker Compose já instalado"
  fi

  # Nginx
  if ! command -v nginx &> /dev/null; then
    log_info "Instalando Nginx..."
    apt-get install -y -qq nginx
    systemctl enable nginx
    systemctl start nginx
    log_success "Nginx instalado"
  else
    log_success "Nginx já instalado"
  fi

  # Certbot
  if ! command -v certbot &> /dev/null; then
    log_info "Instalando Certbot..."
    apt-get install -y -qq certbot python3-certbot-nginx
    log_success "Certbot instalado"
  else
    log_success "Certbot já instalado"
  fi

  # Git
  if ! command -v git &> /dev/null; then
    apt-get install -y -qq git
  fi

  # jq e openssl
  apt-get install -y -qq jq openssl > /dev/null 2>&1 || true
}

# ---- Clonar repositório ----
clone_repo() {
  log_step "PASSO 2/8 — Clonando repositório"

  if [ -d "$INSTALL_DIR/.git" ]; then
    log_info "Repositório já existe, atualizando..."
    cd "$INSTALL_DIR"
    git fetch origin
    git reset --hard origin/main 2>/dev/null || git reset --hard origin/master
    log_success "Repositório atualizado"
  else
    log_info "Clonando de $REPO_URL..."
    rm -rf "$INSTALL_DIR"
    git clone "$REPO_URL" "$INSTALL_DIR"
    log_success "Repositório clonado em $INSTALL_DIR"
  fi

  cd "$INSTALL_DIR/docker"
  mkdir -p "$BACKUP_DIR"
}

# ---- Gerar chaves e configurar .env ----
generate_config() {
  log_step "PASSO 3/8 — Gerando chaves e configuração"

  # Gerar senhas e segredos
  JWT_SECRET=$(openssl rand -base64 32)
  POSTGRES_PASSWORD=$(openssl rand -base64 24 | tr -d '=/+' | head -c 32)

  log_info "Gerando JWT keys via Node.js (Docker)..."

  # Usar Node.js via Docker para gerar JWTs corretamente
  ANON_KEY=$(docker run --rm node:20-alpine node -e "
    const crypto = require('crypto');
    const header = Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url');
    const payload = Buffer.from(JSON.stringify({ref:'simply',role:'anon',iss:'supabase',iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+315360000})).toString('base64url');
    const sig = crypto.createHmac('sha256','${JWT_SECRET}').update(header+'.'+payload).digest('base64url');
    console.log(header+'.'+payload+'.'+sig);
  ")

  SERVICE_ROLE_KEY=$(docker run --rm node:20-alpine node -e "
    const crypto = require('crypto');
    const header = Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url');
    const payload = Buffer.from(JSON.stringify({ref:'simply',role:'service_role',iss:'supabase',iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+315360000})).toString('base64url');
    const sig = crypto.createHmac('sha256','${JWT_SECRET}').update(header+'.'+payload).digest('base64url');
    console.log(header+'.'+payload+'.'+sig);
  ")

  if [ -z "$ANON_KEY" ] || [ -z "$SERVICE_ROLE_KEY" ]; then
    log_error "Falha ao gerar JWT keys. Verifique se o Docker está funcionando."
    exit 1
  fi

  # Criar .env
  cat > "$INSTALL_DIR/docker/.env" << ENVEOF
############################################################
# Simply Imóveis - Configuração de Produção
# Gerado automaticamente em $(date)
############################################################

# ========== DOMÍNIO ==========
SITE_DOMAIN=${DOMAIN}

# ========== BANCO DE DADOS ==========
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=simply_db

# ========== JWT ==========
JWT_SECRET=${JWT_SECRET}
ANON_KEY=${ANON_KEY}
SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY}

# ========== SMTP (configure depois se necessário) ==========
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=
SMTP_PASS=
SMTP_SENDER_NAME="Simply Imóveis"
SMTP_ADMIN_EMAIL=${ADMIN_EMAIL}

# ========== GROQ API (Chat Luma) ==========
GROQ_API_KEY=${GROQ_KEY}

# ========== TELEGRAM ==========
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID}

# ========== PORTAS ==========
KONG_HTTP_PORT=8000
FRONTEND_PORT=3000
ENVEOF

  chmod 600 "$INSTALL_DIR/docker/.env"
  log_success "Arquivo .env gerado com chaves seguras"
  log_success "JWT_SECRET: ${JWT_SECRET:0:20}..."
  log_success "ANON_KEY gerada (${#ANON_KEY} chars)"
  log_success "SERVICE_ROLE_KEY gerada (${#SERVICE_ROLE_KEY} chars)"
}

# ---- Preparar Edge Functions ----
prepare_functions() {
  log_step "PASSO 4/8 — Preparando Edge Functions"

  FUNC_DIR="$INSTALL_DIR/docker/volumes/functions"
  mkdir -p "$FUNC_DIR/main" "$FUNC_DIR/chat" "$FUNC_DIR/notify-telegram" "$FUNC_DIR/create-admin-user"

  # Copiar funções do repo
  cp "$INSTALL_DIR/supabase/functions/chat/index.ts" "$FUNC_DIR/chat/index.ts"
  cp "$INSTALL_DIR/supabase/functions/create-admin-user/index.ts" "$FUNC_DIR/create-admin-user/index.ts"

  # Criar notify-telegram adaptado para self-hosted (sem Lovable gateway)
  cat > "$FUNC_DIR/notify-telegram/index.ts" << 'FUNCEOF'
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const TELEGRAM_BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN");
    if (!TELEGRAM_BOT_TOKEN) {
      console.warn("TELEGRAM_BOT_TOKEN not set, skipping");
      return new Response(JSON.stringify({ ok: true, skipped: true }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const TELEGRAM_CHAT_ID = Deno.env.get("TELEGRAM_CHAT_ID");
    if (!TELEGRAM_CHAT_ID) {
      console.warn("TELEGRAM_CHAT_ID not set, skipping");
      return new Response(JSON.stringify({ ok: true, skipped: true }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { visit } = await req.json();

    const text = `🏠 <b>Nova Visita Agendada!</b>

👤 <b>Cliente:</b> ${visit.client_name}
📱 <b>Telefone:</b> ${visit.client_phone}
${visit.client_email ? `📧 <b>Email:</b> ${visit.client_email}\n` : ""}
🏡 <b>Imóvel:</b> ${visit.property_title || "Não especificado"}
📍 <b>Endereço:</b> ${visit.property_address || "Não especificado"}

📅 <b>Data:</b> ${visit.preferred_date}
🕐 <b>Horário:</b> ${visit.preferred_time}
${visit.notes ? `📝 <b>Obs:</b> ${visit.notes}` : ""}`;

    const response = await fetch(
      `https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          chat_id: TELEGRAM_CHAT_ID,
          text,
          parse_mode: "HTML",
        }),
      }
    );

    const data = await response.json();
    if (!response.ok) {
      throw new Error(`Telegram API failed: ${JSON.stringify(data)}`);
    }

    return new Response(JSON.stringify({ ok: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("notify-telegram error:", e);
    return new Response(JSON.stringify({ error: e.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
FUNCEOF

  # Criar/atualizar main handler
  bash "$INSTALL_DIR/docker/render-functions-main.sh" "$FUNC_DIR"

  log_success "Edge Functions preparadas (chat, notify-telegram, create-admin-user)"
}

# ---- Build e Start dos containers ----
start_containers() {
  log_step "PASSO 5/8 — Construindo e iniciando containers"

  cd "$INSTALL_DIR/docker"

  log_info "Fazendo pull das imagens..."
  docker compose pull --quiet 2>/dev/null || true

  log_info "Construindo frontend..."
  docker compose build --no-cache frontend

  log_info "Iniciando todos os serviços..."
  docker compose up -d

  # Aguardar banco ficar pronto
  log_info "Aguardando banco de dados..."
  local retries=0
  until docker compose exec -T db pg_isready -U supabase_admin -d simply_db > /dev/null 2>&1; do
    retries=$((retries + 1))
    if [ $retries -ge 30 ]; then
      log_error "Banco de dados não iniciou em 60s. Verifique: docker compose logs db"
      exit 1
    fi
    sleep 2
  done
  log_success "Banco de dados pronto"

  # Aguardar Auth
  log_info "Aguardando serviço de autenticação..."
  retries=0
  until docker compose exec -T auth wget -qO- http://localhost:9999/health > /dev/null 2>&1; do
    retries=$((retries + 1))
    if [ $retries -ge 20 ]; then
      log_warn "Auth demorou para iniciar, continuando..."
      break
    fi
    sleep 3
  done
  log_success "Auth pronto"

  # Verificar todos os containers
  echo ""
  log_info "Status dos containers:"
  docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
}

# ---- Configurar Nginx ----
configure_nginx() {
  log_step "PASSO 6/8 — Configurando Nginx"

  local NGINX_CONF="/etc/nginx/sites-available/simplyimoveis.conf"

  cat > "$NGINX_CONF" << NGINXEOF
# ============================================================
# Simply Imóveis - Nginx Config (gerado automaticamente)
# ============================================================

server {
    listen 80;
    server_name ${DOMAIN} www.${DOMAIN};

    # Certbot vai redirecionar para HTTPS após gerar o certificado
    
    client_max_body_size 50M;

    # Frontend
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # API (Supabase via Kong)
    location /api/ {
        proxy_pass http://127.0.0.1:8000/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # SSE/Streaming para chat
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 300s;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINXEOF

  # Criar symlink se não existir
  ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/simplyimoveis.conf

  # Testar configuração
  if nginx -t 2>/dev/null; then
    systemctl reload nginx
    log_success "Nginx configurado e recarregado"
  else
    log_error "Erro na configuração do Nginx. Verifique: nginx -t"
    nginx -t
    exit 1
  fi
}

# ---- SSL com Certbot ----
setup_ssl() {
  log_step "PASSO 7/8 — Configurando SSL (HTTPS)"

  log_info "Verificando DNS do domínio ${DOMAIN}..."

  # Verificar se domínio resolve para este servidor
  local server_ip
  server_ip=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "unknown")
  local domain_ip
  domain_ip=$(dig +short "$DOMAIN" 2>/dev/null | head -1)

  if [ "$server_ip" = "$domain_ip" ]; then
    log_success "DNS OK: ${DOMAIN} → ${server_ip}"
  else
    log_warn "DNS pode não estar apontando para este servidor"
    log_warn "IP do servidor: ${server_ip}"
    log_warn "IP do domínio:  ${domain_ip:-não resolvido}"
    echo ""
    read -p "$(echo -e "${BOLD}Continuar com SSL mesmo assim? (s/N)${NC}: ")" ssl_confirm
    if [[ ! "$ssl_confirm" =~ ^[sS]$ ]]; then
      log_warn "SSL não configurado. Execute depois: certbot --nginx -d ${DOMAIN} -d www.${DOMAIN}"
      return
    fi
  fi

  log_info "Gerando certificado SSL..."
  certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos -m "$ADMIN_EMAIL" --redirect 2>&1 || {
    log_warn "Certbot falhou. Tente manualmente: certbot --nginx -d ${DOMAIN} -d www.${DOMAIN}"
    return
  }

  # Configurar renovação automática
  if ! crontab -l 2>/dev/null | grep -q certbot; then
    (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --post-hook 'systemctl reload nginx'") | crontab -
    log_success "Renovação automática de SSL configurada (cron 3h)"
  fi

  log_success "SSL configurado com sucesso!"
}

# ---- Criar admin e finalizar ----
create_admin_and_finish() {
  log_step "PASSO 8/8 — Criando usuário administrador"

  cd "$INSTALL_DIR/docker"

  # Aguardar um pouco mais para garantir que tudo está pronto
  sleep 5

  # Criar admin via GoTrue API diretamente
  log_info "Criando admin: ${ADMIN_EMAIL}..."

  # Ler variáveis do .env
  source .env

  local RUNTIME_SERVICE_KEY
  RUNTIME_SERVICE_KEY=$(docker compose exec -T kong printenv SUPABASE_SERVICE_KEY 2>/dev/null | tr -d '\r' || true)
  local API_SERVICE_KEY
  API_SERVICE_KEY="${RUNTIME_SERVICE_KEY:-${SERVICE_ROLE_KEY:-}}"

  if [ -z "$API_SERVICE_KEY" ]; then
    log_error "SERVICE_ROLE_KEY indisponível para criar o admin"
    return
  fi

  if [ -n "$RUNTIME_SERVICE_KEY" ] && [ "${SERVICE_ROLE_KEY:-}" != "$RUNTIME_SERVICE_KEY" ]; then
    log_warn "Chave do .env diferente da chave ativa do Kong, usando chave do container"
  fi

  local AUTH_RESPONSE
  AUTH_RESPONSE=$(curl -s -X POST \
    "http://127.0.0.1:${KONG_HTTP_PORT:-8000}/auth/v1/admin/users" \
    -H "Content-Type: application/json" \
    -H "apikey: ${API_SERVICE_KEY}" \
    -H "Authorization: Bearer ${API_SERVICE_KEY}" \
    -d "{
      \"email\": \"${ADMIN_EMAIL}\",
      \"password\": \"${ADMIN_PASS}\",
      \"email_confirm\": true,
      \"user_metadata\": {\"name\": \"Administrador\"}
    }" 2>/dev/null)

  local USER_ID
  USER_ID=$(echo "$AUTH_RESPONSE" | jq -r '.id // empty' 2>/dev/null)

  if [ -n "$USER_ID" ] && [ "$USER_ID" != "null" ]; then
    log_success "Usuário criado: ${ADMIN_EMAIL} (ID: ${USER_ID})"

    # Inserir role de admin via PostgREST
    curl -s -X POST \
      "http://127.0.0.1:${KONG_HTTP_PORT:-8000}/rest/v1/user_roles" \
      -H "Content-Type: application/json" \
      -H "apikey: ${API_SERVICE_KEY}" \
      -H "Authorization: Bearer ${API_SERVICE_KEY}" \
      -H "Prefer: return=minimal" \
      -d "{\"user_id\": \"${USER_ID}\", \"role\": \"admin\"}" > /dev/null 2>&1

    log_success "Role 'admin' atribuída"
  else
    local ERROR_MSG
    ERROR_MSG=$(echo "$AUTH_RESPONSE" | jq -r '.msg // .message // .error // "Erro desconhecido"' 2>/dev/null)
    if echo "$ERROR_MSG" | grep -qi "already"; then
      log_warn "Usuário já existe: ${ADMIN_EMAIL}"
    else
      log_warn "Erro ao criar admin: ${ERROR_MSG}"
      log_info "Tente manualmente: bash ${INSTALL_DIR}/docker/create-admin.sh ${ADMIN_EMAIL} <senha>"
    fi
  fi

  # Configurar backup automático
  log_info "Configurando backup automático..."
  if ! crontab -l 2>/dev/null | grep -q "simply.*backup"; then
    (crontab -l 2>/dev/null; echo "0 2 * * * ${INSTALL_DIR}/docker/backup.sh >> /var/log/simply-backup.log 2>&1") | crontab -
    log_success "Backup diário configurado (2h da manhã)"
  else
    log_success "Backup automático já configurado"
  fi
}

# ---- Resumo final ----
print_summary() {
  local HAS_SSL="Não"
  if [ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]; then
    HAS_SSL="Sim"
  fi

  source "$INSTALL_DIR/docker/.env"

  echo ""
  echo -e "${GREEN}"
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║                                                          ║"
  echo "║   ✅ SIMPLY IMÓVEIS - INSTALAÇÃO CONCLUÍDA!             ║"
  echo "║                                                          ║"
  echo "╠══════════════════════════════════════════════════════════╣"
  echo "║                                                          ║"
  echo "║   🌐 Site:    https://${DOMAIN}                          "
  echo "║   🔑 Admin:   https://${DOMAIN}/admin                   "
  echo "║   📧 Login:   ${ADMIN_EMAIL}                            "
  echo "║   🔒 SSL:     ${HAS_SSL}                                "
  echo "║                                                          ║"
  echo "╠══════════════════════════════════════════════════════════╣"
  echo "║                                                          ║"
  echo "║   📂 Diretório:  ${INSTALL_DIR}                         "
  echo "║   📋 Logs:       docker compose logs -f                 "
  echo "║   🔄 Restart:    docker compose restart                 "
  echo "║   💾 Backup:     bash backup.sh                         "
  echo "║                                                          ║"
  echo "╠══════════════════════════════════════════════════════════╣"
  echo "║                                                          ║"
  echo "║   ⚙️  SMTP não configurado - edite o .env:              "
  echo "║      nano ${INSTALL_DIR}/docker/.env                    "
  echo "║      docker compose restart auth                        "
  echo "║                                                          ║"
  echo "╚══════════════════════════════════════════════════════════╝"
  echo -e "${NC}"

  echo ""
  echo -e "${YELLOW}Senhas salvas em: ${INSTALL_DIR}/docker/.env${NC}"
  echo -e "${YELLOW}NUNCA compartilhe este arquivo!${NC}"
  echo ""

  # Salvar resumo da instalação
  cat > "$INSTALL_DIR/INSTALL_INFO.txt" << INFOEOF
Simply Imóveis - Informações da Instalação
==========================================
Data: $(date)
Domínio: ${DOMAIN}
Admin Email: ${ADMIN_EMAIL}
SSL: ${HAS_SSL}
Diretório: ${INSTALL_DIR}

Comandos úteis:
  cd ${INSTALL_DIR}/docker
  docker compose logs -f         # Ver logs
  docker compose restart         # Reiniciar
  docker compose down            # Parar
  docker compose up -d --build frontend  # Rebuild frontend
  bash backup.sh                 # Backup manual
  bash restore.sh <arquivo.gz>   # Restaurar backup

Atualizar o sistema:
  cd ${INSTALL_DIR}
  git pull
  cd docker
  docker compose up -d --build frontend

Configurar SMTP:
  nano ${INSTALL_DIR}/docker/.env
  docker compose restart auth
INFOEOF
}

# ---- Execução ----
banner
check_root
collect_info
install_system_deps
clone_repo
generate_config
prepare_functions
start_containers
configure_nginx
setup_ssl
create_admin_and_finish
print_summary
