#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

[ -f "$ENV_FILE" ] || { echo "❌ .env não encontrado em $ENV_FILE"; exit 1; }

read_env() {
  grep -E "^${1}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"
}

compose() {
  docker compose -f "$COMPOSE_FILE" --project-directory "$SCRIPT_DIR" "$@"
}

run_sql() {
  compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" db \
    psql -At -P pager=off -w -h 127.0.0.1 -U "$DB_USER" -d "$POSTGRES_DB" -c "$1"
}

preview_body() {
  tr '\n' ' ' < "$1" 2>/dev/null | sed 's/  */ /g' | cut -c1-220
}

print_headers() {
  grep -Ei '^(HTTP/|content-type:|content-length:|www-authenticate:|x-kong-)' "$1" || true
}

fetch_url() {
  local url="$1"
  local body_file="$2"
  local headers_file="$3"

  curl -sS -L -m 20 -D "$headers_file" -o "$body_file" -w "%{http_code}" "$url" 2>/dev/null || echo "000"
}

KONG_PORT="$(read_env "KONG_HTTP_PORT")"; KONG_PORT="${KONG_PORT:-8000}"
ANON_KEY="$(read_env "ANON_KEY")"
POSTGRES_PASSWORD="$(read_env "POSTGRES_PASSWORD")"
POSTGRES_DB="$(read_env "POSTGRES_DB")"; POSTGRES_DB="${POSTGRES_DB:-simply_db}"
DB_USER="$(read_env "POSTGRES_USER")"; DB_USER="${DB_USER:-supabase_admin}"
SITE_DOMAIN="$(read_env "SITE_DOMAIN")"

MEDIA_PATH="${1:-}"
if [ -z "$MEDIA_PATH" ]; then
  MEDIA_PATH="$(run_sql "SELECT file_path FROM public.property_media ORDER BY created_at DESC LIMIT 1;")"
fi

[ -n "$MEDIA_PATH" ] || {
  echo "❌ Nenhuma mídia encontrada em public.property_media. Informe o file_path manualmente."
  echo "Uso: bash docker/debug-public-media.sh usuario/property-id/arquivo.jpg"
  exit 1
}

ENCODED_PATH=$(python3 - "$MEDIA_PATH" <<'PY'
import sys
from urllib.parse import quote

path = sys.argv[1].strip()
print('/'.join(quote(part, safe='') for part in path.split('/')))
PY
)

DIRECT_URL_NO_KEY="http://127.0.0.1:${KONG_PORT}/storage/v1/object/public/property-media/${ENCODED_PATH}"
DIRECT_URL_WITH_KEY="${DIRECT_URL_NO_KEY}?apikey=${ANON_KEY}"
PUBLIC_URL=""

if [ -n "$SITE_DOMAIN" ]; then
  PUBLIC_URL="https://${SITE_DOMAIN}/api/storage/v1/object/public/property-media/${ENCODED_PATH}?apikey=${ANON_KEY}"
fi

echo "══════════════════════════════════════════════════"
echo "  Debug Public Media (self-hosted)"
echo "══════════════════════════════════════════════════"
echo
echo "file_path: $MEDIA_PATH"
echo "encoded : $ENCODED_PATH"
echo

NO_KEY_HTTP=$(fetch_url "$DIRECT_URL_NO_KEY" /tmp/public-media-no-key.body /tmp/public-media-no-key.headers)
echo "1) Gateway direto sem apikey"
echo "URL : $DIRECT_URL_NO_KEY"
echo "HTTP: $NO_KEY_HTTP"
print_headers /tmp/public-media-no-key.headers
echo "Body: $(preview_body /tmp/public-media-no-key.body)"
echo

WITH_KEY_HTTP=$(fetch_url "$DIRECT_URL_WITH_KEY" /tmp/public-media-with-key.body /tmp/public-media-with-key.headers)
echo "2) Gateway direto com apikey na query"
echo "URL : $DIRECT_URL_WITH_KEY"
echo "HTTP: $WITH_KEY_HTTP"
print_headers /tmp/public-media-with-key.headers
if [ "$WITH_KEY_HTTP" = "200" ]; then
  echo "Bytes: $(wc -c < /tmp/public-media-with-key.body | tr -d ' ')"
else
  echo "Body: $(preview_body /tmp/public-media-with-key.body)"
fi
echo

if [ -n "$PUBLIC_URL" ]; then
  PUBLIC_HTTP=$(fetch_url "$PUBLIC_URL" /tmp/public-media-public.body /tmp/public-media-public.headers)
  echo "3) URL final do frontend (/api)"
  echo "URL : $PUBLIC_URL"
  echo "HTTP: $PUBLIC_HTTP"
  print_headers /tmp/public-media-public.headers
  if [ "$PUBLIC_HTTP" = "200" ]; then
    echo "Bytes: $(wc -c < /tmp/public-media-public.body | tr -d ' ')"
  else
    echo "Body: $(preview_body /tmp/public-media-public.body)"
  fi
  echo
else
  echo "3) URL final do frontend (/api)"
  echo "⚠️ SITE_DOMAIN não definido no .env; teste manual esperado:"
  echo "   https://SEU-DOMINIO/api/storage/v1/object/public/property-media/${ENCODED_PATH}?apikey=${ANON_KEY}"
  echo
fi

echo "4) Último registro de mídia no banco"
run_sql "SELECT id, property_id, file_type, created_at, file_path FROM public.property_media ORDER BY created_at DESC LIMIT 1;"