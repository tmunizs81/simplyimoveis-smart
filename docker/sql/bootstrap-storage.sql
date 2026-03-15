-- ============================================================
-- Simply Imóveis - Bootstrap de Storage (idempotente)
-- Executar somente após bootstrap core (types/tables/functions)
-- ============================================================

BEGIN;

DO $$
BEGIN
  IF to_regclass('storage.buckets') IS NULL OR to_regclass('storage.objects') IS NULL THEN
    RAISE EXCEPTION 'Storage schema não está pronto (storage.buckets/storage.objects ausentes).';
  END IF;

  IF to_regclass('public.user_roles') IS NULL THEN
    RAISE EXCEPTION 'Dependência ausente: public.user_roles';
  END IF;

  IF to_regprocedure('public.has_role_text(uuid,text)') IS NULL THEN
    RAISE EXCEPTION 'Dependência ausente: public.has_role_text(uuid,text)';
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
  WITH CHECK (bucket_id = 'contract-documents' AND public.has_role_text(auth.uid(), 'admin'));
CREATE POLICY "Admins can read contract-documents"
  ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'contract-documents' AND public.has_role_text(auth.uid(), 'admin'));
CREATE POLICY "Admins can update contract-documents"
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'contract-documents' AND public.has_role_text(auth.uid(), 'admin'))
  WITH CHECK (bucket_id = 'contract-documents' AND public.has_role_text(auth.uid(), 'admin'));
CREATE POLICY "Admins can delete contract-documents"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'contract-documents' AND public.has_role_text(auth.uid(), 'admin'));

CREATE POLICY "Admins can upload tenant-documents"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'tenant-documents' AND public.has_role_text(auth.uid(), 'admin'));
CREATE POLICY "Admins can read tenant-documents"
  ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'tenant-documents' AND public.has_role_text(auth.uid(), 'admin'));
CREATE POLICY "Admins can update tenant-documents"
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'tenant-documents' AND public.has_role_text(auth.uid(), 'admin'))
  WITH CHECK (bucket_id = 'tenant-documents' AND public.has_role_text(auth.uid(), 'admin'));
CREATE POLICY "Admins can delete tenant-documents"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'tenant-documents' AND public.has_role_text(auth.uid(), 'admin'));

CREATE POLICY "Admins can upload inspection-media"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'inspection-media' AND public.has_role_text(auth.uid(), 'admin'));
CREATE POLICY "Admins can read inspection-media"
  ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'inspection-media' AND public.has_role_text(auth.uid(), 'admin'));
CREATE POLICY "Admins can update inspection-media"
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'inspection-media' AND public.has_role_text(auth.uid(), 'admin'))
  WITH CHECK (bucket_id = 'inspection-media' AND public.has_role_text(auth.uid(), 'admin'));
CREATE POLICY "Admins can delete inspection-media"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'inspection-media' AND public.has_role_text(auth.uid(), 'admin'));

CREATE POLICY "Admins can upload sales-documents"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'sales-documents' AND public.has_role_text(auth.uid(), 'admin'));
CREATE POLICY "Admins can read sales-documents"
  ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'sales-documents' AND public.has_role_text(auth.uid(), 'admin'));
CREATE POLICY "Admins can update sales-documents"
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'sales-documents' AND public.has_role_text(auth.uid(), 'admin'))
  WITH CHECK (bucket_id = 'sales-documents' AND public.has_role_text(auth.uid(), 'admin'));
CREATE POLICY "Admins can delete sales-documents"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'sales-documents' AND public.has_role_text(auth.uid(), 'admin'));

CREATE POLICY "Admins can upload property-media"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'property-media' AND public.has_role_text(auth.uid(), 'admin'));
CREATE POLICY "Admins can update property-media"
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'property-media' AND public.has_role_text(auth.uid(), 'admin'))
  WITH CHECK (bucket_id = 'property-media' AND public.has_role_text(auth.uid(), 'admin'));
CREATE POLICY "Admins can delete property-media"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'property-media' AND public.has_role_text(auth.uid(), 'admin'));
CREATE POLICY "Public can read property-media"
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'property-media');

COMMIT;
