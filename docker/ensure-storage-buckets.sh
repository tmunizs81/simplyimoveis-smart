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
  psql -v ON_ERROR_STOP=1 -w -h 127.0.0.1 -U "$DB_ADMIN_USER" -d "$POSTGRES_DB" <<'EOSQL'
DO $$
BEGIN
  IF to_regclass('storage.buckets') IS NULL OR to_regclass('storage.objects') IS NULL THEN
    RAISE NOTICE 'storage schema ainda não está pronto; pulando por enquanto';
    RETURN;
  END IF;

  INSERT INTO storage.buckets (id, name, public) VALUES
    ('property-media', 'property-media', true),
    ('contract-documents', 'contract-documents', false),
    ('tenant-documents', 'tenant-documents', false),
    ('inspection-media', 'inspection-media', false),
    ('sales-documents', 'sales-documents', false)
  ON CONFLICT (id) DO NOTHING;

  ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

  DROP POLICY IF EXISTS "Admins can upload contract-documents" ON storage.objects;
  DROP POLICY IF EXISTS "Admins can read contract-documents" ON storage.objects;
  DROP POLICY IF EXISTS "Admins can update contract-documents" ON storage.objects;
  DROP POLICY IF EXISTS "Admins can delete contract-documents" ON storage.objects;

  DROP POLICY IF EXISTS "Admins can upload tenant-documents" ON storage.objects;
  DROP POLICY IF EXISTS "Admins can read tenant-documents" ON storage.objects;
  DROP POLICY IF EXISTS "Admins can update tenant-documents" ON storage.objects;
  DROP POLICY IF EXISTS "Admins can delete tenant-documents" ON storage.objects;

  DROP POLICY IF EXISTS "Admins can upload inspection-media" ON storage.objects;
  DROP POLICY IF EXISTS "Admins can read inspection-media" ON storage.objects;
  DROP POLICY IF EXISTS "Admins can update inspection-media" ON storage.objects;
  DROP POLICY IF EXISTS "Admins can delete inspection-media" ON storage.objects;

  DROP POLICY IF EXISTS "Admins can upload sales-documents" ON storage.objects;
  DROP POLICY IF EXISTS "Admins can read sales-documents" ON storage.objects;
  DROP POLICY IF EXISTS "Admins can update sales-documents" ON storage.objects;
  DROP POLICY IF EXISTS "Admins can delete sales-documents" ON storage.objects;

  DROP POLICY IF EXISTS "Admins can upload property-media" ON storage.objects;
  DROP POLICY IF EXISTS "Admins can update property-media" ON storage.objects;
  DROP POLICY IF EXISTS "Admins can delete property-media" ON storage.objects;
  DROP POLICY IF EXISTS "Public can read property-media" ON storage.objects;

  CREATE POLICY "Admins can upload contract-documents"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'contract-documents' AND public.has_role(auth.uid(), 'admin'::public.app_role));
  CREATE POLICY "Admins can read contract-documents"
    ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'contract-documents' AND public.has_role(auth.uid(), 'admin'::public.app_role));
  CREATE POLICY "Admins can update contract-documents"
    ON storage.objects FOR UPDATE TO authenticated
    USING (bucket_id = 'contract-documents' AND public.has_role(auth.uid(), 'admin'::public.app_role))
    WITH CHECK (bucket_id = 'contract-documents' AND public.has_role(auth.uid(), 'admin'::public.app_role));
  CREATE POLICY "Admins can delete contract-documents"
    ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id = 'contract-documents' AND public.has_role(auth.uid(), 'admin'::public.app_role));

  CREATE POLICY "Admins can upload tenant-documents"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'tenant-documents' AND public.has_role(auth.uid(), 'admin'::public.app_role));
  CREATE POLICY "Admins can read tenant-documents"
    ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'tenant-documents' AND public.has_role(auth.uid(), 'admin'::public.app_role));
  CREATE POLICY "Admins can update tenant-documents"
    ON storage.objects FOR UPDATE TO authenticated
    USING (bucket_id = 'tenant-documents' AND public.has_role(auth.uid(), 'admin'::public.app_role))
    WITH CHECK (bucket_id = 'tenant-documents' AND public.has_role(auth.uid(), 'admin'::public.app_role));
  CREATE POLICY "Admins can delete tenant-documents"
    ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id = 'tenant-documents' AND public.has_role(auth.uid(), 'admin'::public.app_role));

  CREATE POLICY "Admins can upload inspection-media"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'inspection-media' AND public.has_role(auth.uid(), 'admin'::public.app_role));
  CREATE POLICY "Admins can read inspection-media"
    ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'inspection-media' AND public.has_role(auth.uid(), 'admin'::public.app_role));
  CREATE POLICY "Admins can update inspection-media"
    ON storage.objects FOR UPDATE TO authenticated
    USING (bucket_id = 'inspection-media' AND public.has_role(auth.uid(), 'admin'::public.app_role))
    WITH CHECK (bucket_id = 'inspection-media' AND public.has_role(auth.uid(), 'admin'::public.app_role));
  CREATE POLICY "Admins can delete inspection-media"
    ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id = 'inspection-media' AND public.has_role(auth.uid(), 'admin'::public.app_role));

  CREATE POLICY "Admins can upload sales-documents"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'sales-documents' AND public.has_role(auth.uid(), 'admin'::public.app_role));
  CREATE POLICY "Admins can read sales-documents"
    ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'sales-documents' AND public.has_role(auth.uid(), 'admin'::public.app_role));
  CREATE POLICY "Admins can update sales-documents"
    ON storage.objects FOR UPDATE TO authenticated
    USING (bucket_id = 'sales-documents' AND public.has_role(auth.uid(), 'admin'::public.app_role))
    WITH CHECK (bucket_id = 'sales-documents' AND public.has_role(auth.uid(), 'admin'::public.app_role));
  CREATE POLICY "Admins can delete sales-documents"
    ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id = 'sales-documents' AND public.has_role(auth.uid(), 'admin'::public.app_role));

  CREATE POLICY "Admins can upload property-media"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'property-media' AND public.has_role(auth.uid(), 'admin'::public.app_role));
  CREATE POLICY "Admins can update property-media"
    ON storage.objects FOR UPDATE TO authenticated
    USING (bucket_id = 'property-media' AND public.has_role(auth.uid(), 'admin'::public.app_role))
    WITH CHECK (bucket_id = 'property-media' AND public.has_role(auth.uid(), 'admin'::public.app_role));
  CREATE POLICY "Admins can delete property-media"
    ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id = 'property-media' AND public.has_role(auth.uid(), 'admin'::public.app_role));
  CREATE POLICY "Public can read property-media"
    ON storage.objects FOR SELECT TO public
    USING (bucket_id = 'property-media');
END $$;
EOSQL

echo "✅ Buckets padrão verificados/criados"