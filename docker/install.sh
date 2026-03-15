#!/bin/bash
set -euo pipefail

# ============================================================
# Simply Imóveis - Instalador Docker para Ubuntu 24.04
# Uso: sudo bash install.sh
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# ---- Gerar .env se não existir ----
if [ ! -f .env ]; then
  echo -e "${YELLOW}📝 Gerando arquivo .env...${NC}"
  cp .env.example .env

  # Gerar JWT_SECRET
  JWT_SECRET=$(openssl rand -base64 32)
  sed -i "s|super-secret-jwt-token-with-at-least-32-characters-long|${JWT_SECRET}|g" .env

  # Gerar senha do banco
  PG_PASS=$(openssl rand -base64 24 | tr -d '=/+')
  sed -i "s|SuaSenhaForteAqui123!|${PG_PASS}|g" .env

  echo ""
  echo -e "${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${YELLOW}║  ⚠️  CONFIGURE O ARQUIVO .env ANTES DE CONTINUAR    ║${NC}"
  echo -e "${YELLOW}╠══════════════════════════════════════════════════════╣${NC}"
  echo -e "${YELLOW}║  Arquivo: ${INSTALL_DIR}/docker/.env        ║${NC}"
  echo -e "${YELLOW}║                                                      ║${NC}"
  echo -e "${YELLOW}║  Itens obrigatórios:                                 ║${NC}"
  echo -e "${YELLOW}║  1. SITE_DOMAIN (seu domínio)                        ║${NC}"
  echo -e "${YELLOW}║  2. SMTP_* (configurações de email)                  ║${NC}"
  echo -e "${YELLOW}║  3. GROQ_API_KEY (para o chat da Luma)               ║${NC}"
  echo -e "${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "${BLUE}As chaves ANON_KEY e SERVICE_ROLE_KEY serão geradas automaticamente.${NC}"
  read -p "Pressione ENTER após configurar o .env para continuar..."
fi

# ---- Garantir ANON_KEY/SERVICE_ROLE_KEY válidas ----
if grep -q "CHANGE_ME" .env; then
  echo -e "${BLUE}🔑 Gerando ANON_KEY e SERVICE_ROLE_KEY...${NC}"
  bash generate-keys.sh
fi

# ---- Copiar Edge Functions ----
echo -e "${BLUE}📦 Preparando Edge Functions...${NC}"
mkdir -p volumes/functions/main
mkdir -p volumes/functions/chat
mkdir -p volumes/functions/notify-telegram
mkdir -p volumes/functions/create-admin-user

cp "$INSTALL_DIR/supabase/functions/chat/index.ts" volumes/functions/chat/index.ts
cp "$INSTALL_DIR/supabase/functions/notify-telegram/index.ts" volumes/functions/notify-telegram/index.ts
cp "$INSTALL_DIR/supabase/functions/create-admin-user/index.ts" volumes/functions/create-admin-user/index.ts

# Cria o main handler para edge functions
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

# ---- Build e Start seguro ----
echo -e "${BLUE}🔨 Subindo banco...${NC}"
docker compose up -d --build db

echo -e "${BLUE}🔧 Sincronizando credenciais internas do banco...${NC}"
bash sync-db-passwords.sh

echo -e "${BLUE}🚀 Subindo serviços da stack...${NC}"
docker compose up -d --build --force-recreate auth rest storage functions kong frontend --remove-orphans

echo -e "${BLUE}🧪 Executando validação pós-instalação...${NC}"
bash validate-install.sh

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
echo -e "${GREEN}║  2. Instale SSL: certbot --nginx -d seudominio.com  ║${NC}"
echo -e "${GREEN}║  3. Crie o usuário admin:                            ║${NC}"
echo -e "${GREEN}║     bash create-admin.sh admin@email.com senha123    ║${NC}"
echo -e "${GREEN}║                                                      ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
