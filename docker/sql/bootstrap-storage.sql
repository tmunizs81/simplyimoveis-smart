-- ============================================================
-- Simply Imóveis - Bootstrap de Storage (idempotente)
-- Ordem: dependências auth/roles -> buckets -> RLS -> policies
-- ============================================================

BEGIN;

DO $$
BEGIN
  IF to_regclass('storage.buckets') IS NULL OR to_regclass('storage.objects') IS NULL THEN
    RAISE EXCEPTION 'Dependência ausente: storage.buckets/storage.objects';
  END IF;

  IF to_regclass('public.user_roles') IS NULL THEN
    RAISE EXCEPTION 'Dependência ausente: public.user_roles';
  END IF;

  IF to_regtype('public.app_role') IS NULL THEN
    RAISE EXCEPTION 'Dependência ausente: public.app_role';
  END IF;

  IF to_regprocedure('public.has_role(uuid,public.app_role)') IS NULL THEN
    RAISE EXCEPTION 'Dependência ausente: public.has_role(uuid,public.app_role)';
  END IF;
END
$$;

INSERT INTO storage.buckets (id, name, public) VALUES
  ('property-media', 'property-media', true),
  ('contract-documents', 'contract-documents', false),
  ('tenant-documents', 'tenant-documents', false),
  ('inspection-media', 'inspection-media', false),
  ('sales-documents', 'sales-documents', false)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

GRANT USAGE ON SCHEMA storage TO authenticator, anon, authenticated, service_role;
GRANT SELECT ON TABLE storage.objects TO anon, authenticated, service_role;
GRANT INSERT, UPDATE, DELETE ON TABLE storage.objects TO authenticated, service_role;
GRANT SELECT ON TABLE storage.buckets TO authenticated, service_role;

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
DROP POLICY IF EXISTS "Service role can manage contract-documents" ON storage.objects;
DROP POLICY IF EXISTS "Service role can manage tenant-documents" ON storage.objects;
DROP POLICY IF EXISTS "Service role can manage inspection-media" ON storage.objects;
DROP POLICY IF EXISTS "Service role can manage sales-documents" ON storage.objects;
DROP POLICY IF EXISTS "Service role can manage property-media" ON storage.objects;

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

CREATE POLICY "Service role can manage contract-documents"
  ON storage.objects FOR ALL TO service_role
  USING (bucket_id = 'contract-documents')
  WITH CHECK (bucket_id = 'contract-documents');

CREATE POLICY "Service role can manage tenant-documents"
  ON storage.objects FOR ALL TO service_role
  USING (bucket_id = 'tenant-documents')
  WITH CHECK (bucket_id = 'tenant-documents');

CREATE POLICY "Service role can manage inspection-media"
  ON storage.objects FOR ALL TO service_role
  USING (bucket_id = 'inspection-media')
  WITH CHECK (bucket_id = 'inspection-media');

CREATE POLICY "Service role can manage sales-documents"
  ON storage.objects FOR ALL TO service_role
  USING (bucket_id = 'sales-documents')
  WITH CHECK (bucket_id = 'sales-documents');

CREATE POLICY "Service role can manage property-media"
  ON storage.objects FOR ALL TO service_role
  USING (bucket_id = 'property-media')
  WITH CHECK (bucket_id = 'property-media');

COMMIT;
