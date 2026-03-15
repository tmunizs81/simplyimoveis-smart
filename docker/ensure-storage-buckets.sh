#!/bin/bash
# ============================================================
# Garante buckets padrão após storage migrations
# Uso: bash ensure-storage-buckets.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

[ ! -f .env ] && echo "❌ .env não encontrado" && exit 1

read_env() { grep -E "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"; }

POSTGRES_PASSWORD=$(read_env "POSTGRES_PASSWORD")
POSTGRES_DB=$(read_env "POSTGRES_DB"); POSTGRES_DB="${POSTGRES_DB:-simply_db}"
DB_ADMIN_USER=$(read_env "POSTGRES_USER"); DB_ADMIN_USER="${DB_ADMIN_USER:-supabase_admin}"

[ -z "${POSTGRES_PASSWORD:-}" ] && echo "❌ POSTGRES_PASSWORD vazio" && exit 1

echo "🪣 Garantindo buckets padrão..."

docker compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" db \
  psql -v ON_ERROR_STOP=1 -w -U "$DB_ADMIN_USER" -d "$POSTGRES_DB" <<'EOSQL'
DO $$
BEGIN
  IF to_regclass('storage.buckets') IS NULL THEN
    RAISE NOTICE 'storage.buckets ainda não existe; pulando por enquanto';
    RETURN;
  END IF;

  INSERT INTO storage.buckets (id, name, public) VALUES
    ('property-media', 'property-media', true),
    ('contract-documents', 'contract-documents', false),
    ('tenant-documents', 'tenant-documents', false),
    ('inspection-media', 'inspection-media', false),
    ('sales-documents', 'sales-documents', false)
  ON CONFLICT (id) DO NOTHING;
END $$;
EOSQL

echo "✅ Buckets padrão verificados/criados"