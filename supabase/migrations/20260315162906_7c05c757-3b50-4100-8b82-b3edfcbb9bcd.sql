
-- Storage policies for objects table (correct approach for Supabase)
-- Private buckets: allow authenticated users to upload, read, delete

CREATE POLICY "Auth users can upload to contract-documents"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'contract-documents');

CREATE POLICY "Auth users can read contract-documents"
  ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'contract-documents');

CREATE POLICY "Auth users can delete from contract-documents"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'contract-documents');

CREATE POLICY "Auth users can update contract-documents"
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'contract-documents');

CREATE POLICY "Auth users can upload to tenant-documents"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'tenant-documents');

CREATE POLICY "Auth users can read tenant-documents"
  ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'tenant-documents');

CREATE POLICY "Auth users can delete from tenant-documents"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'tenant-documents');

CREATE POLICY "Auth users can update tenant-documents"
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'tenant-documents');

CREATE POLICY "Auth users can upload to inspection-media"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'inspection-media');

CREATE POLICY "Auth users can read inspection-media"
  ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'inspection-media');

CREATE POLICY "Auth users can delete from inspection-media"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'inspection-media');

CREATE POLICY "Auth users can update inspection-media"
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'inspection-media');

CREATE POLICY "Auth users can upload to sales-documents"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'sales-documents');

CREATE POLICY "Auth users can read sales-documents"
  ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'sales-documents');

CREATE POLICY "Auth users can delete from sales-documents"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'sales-documents');

CREATE POLICY "Auth users can update sales-documents"
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'sales-documents');

CREATE POLICY "Auth users can upload to property-media"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'property-media');

CREATE POLICY "Auth users can delete from property-media"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'property-media');

CREATE POLICY "Anyone can read property-media"
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'property-media');
