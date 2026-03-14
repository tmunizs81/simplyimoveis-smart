
-- =============================================
-- TENANT DOCUMENTS
-- =============================================
CREATE TABLE public.tenant_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES public.tenants(id) ON DELETE CASCADE NOT NULL,
  file_path text NOT NULL,
  file_name text NOT NULL,
  file_type text NOT NULL,
  document_type text NOT NULL DEFAULT 'documento',
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  user_id uuid NOT NULL
);

ALTER TABLE public.tenant_documents ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage tenant docs" ON public.tenant_documents
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

-- =============================================
-- PROPERTY INSPECTIONS (Vistorias)
-- =============================================
CREATE TABLE public.property_inspections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid REFERENCES public.properties(id) ON DELETE CASCADE NOT NULL,
  contract_id uuid REFERENCES public.rental_contracts(id) ON DELETE SET NULL,
  tenant_id uuid REFERENCES public.tenants(id) ON DELETE SET NULL,
  inspection_type text NOT NULL DEFAULT 'entrada',
  inspection_date date NOT NULL DEFAULT CURRENT_DATE,
  inspector_name text,
  status text NOT NULL DEFAULT 'pendente',
  general_notes text,
  rooms_condition text,
  electrical_condition text,
  plumbing_condition text,
  painting_condition text,
  floor_condition text,
  keys_delivered integer DEFAULT 0,
  meter_reading_water text,
  meter_reading_electricity text,
  meter_reading_gas text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  user_id uuid NOT NULL
);

ALTER TABLE public.property_inspections ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage inspections" ON public.property_inspections
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

CREATE TRIGGER update_inspections_updated_at BEFORE UPDATE ON public.property_inspections
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =============================================
-- INSPECTION MEDIA (Photos, Videos, PDFs)
-- =============================================
CREATE TABLE public.inspection_media (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  inspection_id uuid REFERENCES public.property_inspections(id) ON DELETE CASCADE NOT NULL,
  file_path text NOT NULL,
  file_name text NOT NULL,
  file_type text NOT NULL,
  media_category text NOT NULL DEFAULT 'geral',
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  user_id uuid NOT NULL
);

ALTER TABLE public.inspection_media ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage inspection media" ON public.inspection_media
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

-- =============================================
-- STORAGE BUCKETS
-- =============================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('tenant-documents', 'tenant-documents', false)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public)
VALUES ('inspection-media', 'inspection-media', false)
ON CONFLICT (id) DO NOTHING;

-- Storage policies for tenant documents
CREATE POLICY "Admins upload tenant docs"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'tenant-documents' AND public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins view tenant docs"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'tenant-documents' AND public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins delete tenant docs"
ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'tenant-documents' AND public.has_role(auth.uid(), 'admin'));

-- Storage policies for inspection media
CREATE POLICY "Admins upload inspection media"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'inspection-media' AND public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins view inspection media"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'inspection-media' AND public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins delete inspection media"
ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'inspection-media' AND public.has_role(auth.uid(), 'admin'));
