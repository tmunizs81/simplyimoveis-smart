#!/bin/bash
# ============================================================
# Simply Imóveis - Status dos serviços
# Uso: bash status.sh
# ============================================================

BLUE='\033[0;34m'; GREEN='\033[0;32m'; RED='\033[0;31m'
YELLOW='\033[1;33m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Simply Imóveis - Status dos Serviços             ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

SERVICES=("simply-db" "simply-auth" "simply-rest" "simply-storage" "simply-kong" "simply-functions" "simply-frontend")
LABELS=("PostgreSQL" "Auth (GoTrue)" "REST (PostgREST)" "Storage" "API Gateway (Kong)" "Edge Functions" "Frontend")

ALL_OK=true
for i in "${!SERVICES[@]}"; do
  name="${SERVICES[$i]}"
  label="${LABELS[$i]}"
  
  STATUS=$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null || echo "not_found")
  HEALTH=$(docker inspect -f '{{.State.Health.Status}}' "$name" 2>/dev/null || echo "none")
  
  if [ "$STATUS" = "running" ]; then
    if [ "$HEALTH" = "healthy" ] || [ "$HEALTH" = "none" ]; then
      echo -e "   ${GREEN}✅ $label${NC} ($name) — running"
    else
      echo -e "   ${YELLOW}⚠️  $label${NC} ($name) — $HEALTH"
      ALL_OK=false
    fi
  elif [ "$STATUS" = "not_found" ]; then
    echo -e "   ${RED}❌ $label${NC} ($name) — não encontrado"
    ALL_OK=false
  else
    echo -e "   ${RED}❌ $label${NC} ($name) — $STATUS"
    ALL_OK=false
  fi
done

echo ""

# Portas
echo -e "${BLUE}🔌 Portas:${NC}"
for port in 5432 3000 8000; do
  if ss -tlnp 2>/dev/null | grep -q ":${port} " || netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
    echo -e "   ${GREEN}✅ :${port} aberta${NC}"
  else
    echo -e "   ${YELLOW}⚠️  :${port} não detectada${NC}"
  fi
done

echo ""

# Volumes
echo -e "${BLUE}💾 Volumes:${NC}"
for v in $(docker volume ls --filter "name=simply" -q 2>/dev/null); do
  SIZE=$(docker system df -v 2>/dev/null | grep "$v" | awk '{print $4}' || echo "?")
  echo -e "   📦 $v ($SIZE)"
done

echo ""

if [ "$ALL_OK" = "true" ]; then
  echo -e "${GREEN}✅ Todos os serviços estão rodando.${NC}"
else
  echo -e "${YELLOW}⚠️  Alguns serviços não estão saudáveis. Use: docker compose logs <servico>${NC}"
fi
