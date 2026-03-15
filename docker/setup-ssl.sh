#!/bin/bash
# ============================================================
# Configura Nginx + SSL (Let's Encrypt) automaticamente
# Uso: sudo bash setup-ssl.sh [dominio] [email]
# ============================================================

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "❌ Execute com sudo: sudo bash setup-ssl.sh"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f .env ]; then
  echo "❌ Arquivo .env não encontrado em $SCRIPT_DIR"
  exit 1
fi

read_env_var() {
  grep -E "^${1}=" .env 2>/dev/null | head -1 | sed "s/^${1}=//" | tr -d '"' | tr -d "'"
}

DOMAIN="${1:-$(read_env_var "SITE_DOMAIN")}" 
ADMIN_EMAIL="${2:-$(read_env_var "SMTP_ADMIN_EMAIL")}" 
FRONTEND_PORT="$(read_env_var "FRONTEND_PORT")"
KONG_PORT="$(read_env_var "KONG_HTTP_PORT")"

FRONTEND_PORT="${FRONTEND_PORT:-3000}"
KONG_PORT="${KONG_PORT:-8000}"

if [ -z "$DOMAIN" ]; then
  echo "❌ SITE_DOMAIN não definido."
  exit 1
fi

if [ -z "$ADMIN_EMAIL" ]; then
  read -p "Email para avisos de renovação SSL: " ADMIN_EMAIL
fi

if [ -z "$ADMIN_EMAIL" ]; then
  echo "❌ Email é obrigatório para o Certbot."
  exit 1
fi

echo "🔧 Instalando Nginx e Certbot..."
apt-get update -qq
apt-get install -y -qq nginx certbot python3-certbot-nginx

systemctl enable nginx >/dev/null 2>&1 || true
systemctl start nginx >/dev/null 2>&1 || true

NGINX_CONF="/etc/nginx/sites-available/simplyimoveis.conf"

echo "📝 Gerando configuração Nginx para ${DOMAIN}..."
cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    server_name ${DOMAIN} www.${DOMAIN};

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
EOF

rm -f /etc/nginx/sites-enabled/default
ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/simplyimoveis.conf

nginx -t
systemctl reload nginx

echo "🔐 Emitindo certificado SSL para ${DOMAIN} e www.${DOMAIN}..."
if certbot --nginx --non-interactive --agree-tos --email "$ADMIN_EMAIL" \
  -d "$DOMAIN" -d "www.$DOMAIN" --redirect; then
  echo "✅ SSL configurado com sucesso!"
else
  echo "❌ Falha ao emitir SSL. Verifique DNS apontando para este servidor e tente novamente."
  exit 1
fi

echo "🧪 Testando renovação automática..."
certbot renew --dry-run || true

echo "🎉 Nginx + SSL prontos para https://${DOMAIN}"
