#!/bin/bash
# ============================================================
# Simply Imóveis - Full Wipe / Limpeza Total
# Remove TUDO relacionado ao projeto para instalação limpa
# Uso: sudo bash full-wipe.sh [--force]
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

INSTALL_DIR="/opt/simply-imoveis"
BACKUP_DIR="/opt/simply-imoveis/backups"
COMPOSE_PROJECT="docker"  # docker-compose project name (directory name)

echo -e "${RED}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║     ⚠️  FULL WIPE - Simply Imóveis                   ║"
echo "║     Remove TODOS os dados e containers do projeto    ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Inventário do que será removido ──
echo -e "${YELLOW}📋 O que será removido:${NC}"

CONTAINERS=$(docker ps -a --filter "name=simply-" --format "{{.Names}}" 2>/dev/null || true)
[ -n "$CONTAINERS" ] && echo -e "   🐳 Containers: $CONTAINERS"

IMAGES=$(docker images --filter "reference=*simply*" --format "{{.Repository}}:{{.Tag}}" 2>/dev/null || true)
COMPOSE_IMAGES=$(docker images --filter "reference=docker-frontend*" --format "{{.Repository}}:{{.Tag}}" 2>/dev/null || true)
[ -n "$IMAGES" ] && echo -e "   📦 Imagens: $IMAGES"
[ -n "$COMPOSE_IMAGES" ] && echo -e "   📦 Imagens compose: $COMPOSE_IMAGES"

VOLUMES=$(docker volume ls --filter "name=simply" -q 2>/dev/null || true)
COMPOSE_VOLUMES=$(docker volume ls --filter "name=docker_simply" -q 2>/dev/null || true)
ALL_VOLUMES=$(echo -e "$VOLUMES\n$COMPOSE_VOLUMES" | sort -u | grep -v '^$' || true)
[ -n "$ALL_VOLUMES" ] && echo -e "   💾 Volumes: $ALL_VOLUMES"

NETWORKS=$(docker network ls --filter "name=simply" -q 2>/dev/null || true)
[ -n "$NETWORKS" ] && echo -e "   🌐 Networks: $(docker network ls --filter "name=simply" --format "{{.Name}}" 2>/dev/null)"

[ -d "$INSTALL_DIR" ] && echo -e "   📁 Diretório: $INSTALL_DIR"
[ -f "/etc/nginx/sites-enabled/simplyimoveis.conf" ] && echo -e "   🌐 Nginx config: simplyimoveis.conf"
[ -d "/etc/letsencrypt/live/simplyimoveis.com.br" ] && echo -e "   🔐 Certificados SSL"

echo ""

# ── Confirmar ──
if [ "$FORCE" != "true" ]; then
  echo -e "${RED}⚠️  ATENÇÃO: Esta ação é IRREVERSÍVEL!${NC}"
  echo -e "${RED}   Todos os dados, banco, arquivos e configurações serão DESTRUÍDOS.${NC}"
  echo ""

  # Oferecer backup
  if [ -n "$ALL_VOLUMES" ]; then
    read -p "Deseja fazer backup do banco antes? (s/N): " DO_BACKUP
    if [[ "$DO_BACKUP" =~ ^[sS]$ ]]; then
      echo -e "${BLUE}💾 Fazendo backup...${NC}"
      mkdir -p "$BACKUP_DIR"
      DATE=$(date +%Y-%m-%d_%H%M)
      docker exec simply-db pg_dump -U supabase_admin simply_db 2>/dev/null | gzip > "$BACKUP_DIR/pre-wipe-${DATE}.sql.gz" && \
        echo -e "   ${GREEN}✅ Backup salvo em $BACKUP_DIR/pre-wipe-${DATE}.sql.gz${NC}" || \
        echo -e "   ${YELLOW}⚠️  Backup falhou (banco pode não estar rodando)${NC}"
    fi
  fi

  # Backup do .env
  if [ -f "$INSTALL_DIR/docker/.env" ]; then
    read -p "Deseja fazer backup do .env? (S/n): " BACKUP_ENV
    if [[ ! "$BACKUP_ENV" =~ ^[nN]$ ]]; then
      mkdir -p /tmp/simply-backup
      cp "$INSTALL_DIR/docker/.env" "/tmp/simply-backup/.env.backup.$(date +%Y%m%d%H%M)"
      echo -e "   ${GREEN}✅ .env salvo em /tmp/simply-backup/${NC}"
    fi
  fi

  read -p "Digite APAGAR para confirmar o full wipe: " CONFIRM
  if [ "$CONFIRM" != "APAGAR" ]; then
    echo -e "${GREEN}❌ Cancelado.${NC}"
    exit 0
  fi
fi

echo ""
echo -e "${BLUE}🧹 Iniciando limpeza...${NC}"

# ── 1. Parar e remover containers ──
echo -e "${BLUE}   1/7 Parando containers...${NC}"
if [ -f "$INSTALL_DIR/docker/docker-compose.yml" ]; then
  cd "$INSTALL_DIR/docker" 2>/dev/null && docker compose down --remove-orphans --timeout 30 2>/dev/null || true
fi
# Força remoção de qualquer container simply-*
for c in $(docker ps -a --filter "name=simply-" -q 2>/dev/null); do
  docker rm -f "$c" 2>/dev/null || true
done
echo -e "   ${GREEN}✅ Containers removidos${NC}"

# ── 2. Remover volumes ──
echo -e "${BLUE}   2/7 Removendo volumes...${NC}"
for v in $ALL_VOLUMES; do
  docker volume rm -f "$v" 2>/dev/null || true
done
echo -e "   ${GREEN}✅ Volumes removidos${NC}"

# ── 3. Remover networks ──
echo -e "${BLUE}   3/7 Removendo networks...${NC}"
for n in $(docker network ls --filter "name=simply" -q 2>/dev/null); do
  docker network rm "$n" 2>/dev/null || true
done
for n in $(docker network ls --filter "name=docker_simply" -q 2>/dev/null); do
  docker network rm "$n" 2>/dev/null || true
done
echo -e "   ${GREEN}✅ Networks removidos${NC}"

# ── 4. Remover imagens ──
echo -e "${BLUE}   4/7 Removendo imagens do projeto...${NC}"
for img in $(docker images --filter "reference=*simply*" -q 2>/dev/null); do
  docker rmi -f "$img" 2>/dev/null || true
done
for img in $(docker images --filter "reference=docker-frontend*" -q 2>/dev/null); do
  docker rmi -f "$img" 2>/dev/null || true
done
echo -e "   ${GREEN}✅ Imagens removidas${NC}"

# ── 5. Limpar diretório do projeto ──
echo -e "${BLUE}   5/7 Removendo diretório do projeto...${NC}"
if [ -d "$INSTALL_DIR" ]; then
  # Preserva backups se existirem
  if [ -d "$BACKUP_DIR" ] && [ "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
    mkdir -p /tmp/simply-backup
    cp -r "$BACKUP_DIR"/* /tmp/simply-backup/ 2>/dev/null || true
    echo -e "   ${CYAN}📦 Backups preservados em /tmp/simply-backup/${NC}"
  fi
  rm -rf "$INSTALL_DIR"
fi
echo -e "   ${GREEN}✅ Diretório removido${NC}"

# ── 6. Limpar Nginx ──
echo -e "${BLUE}   6/7 Limpando configuração Nginx...${NC}"
rm -f /etc/nginx/sites-enabled/simplyimoveis.conf 2>/dev/null || true
rm -f /etc/nginx/sites-available/simplyimoveis.conf 2>/dev/null || true
systemctl reload nginx 2>/dev/null || true
echo -e "   ${GREEN}✅ Nginx limpo${NC}"

# ── 7. Limpar caches Docker ──
echo -e "${BLUE}   7/7 Limpando caches Docker...${NC}"
docker builder prune -f 2>/dev/null || true
echo -e "   ${GREEN}✅ Caches limpos${NC}"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     ✅ Full wipe concluído!                          ║${NC}"
echo -e "${GREEN}║     O ambiente está limpo para nova instalação.      ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"

if [ -d "/tmp/simply-backup" ] && [ "$(ls -A /tmp/simply-backup 2>/dev/null)" ]; then
  echo -e "\n${CYAN}📦 Backups preservados em /tmp/simply-backup/${NC}"
fi

echo -e "\n${BLUE}Próximo passo: sudo bash install.sh${NC}"
