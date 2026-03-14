
-- Create sales_documents table
CREATE TABLE public.sales_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_id uuid NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  document_type text NOT NULL DEFAULT 'documento',
  file_name text NOT NULL,
  file_path text NOT NULL,
  file_type text NOT NULL,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.sales_documents ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage sale docs" ON public.sales_documents
  FOR ALL TO authenticated
  USING (has_role(auth.uid(), 'admin'::app_role));

-- Create storage bucket for sales documents
INSERT INTO storage.buckets (id, name, public) VALUES ('sales-documents', 'sales-documents', false);

-- Storage RLS policies
CREATE POLICY "Admins can upload sale docs" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'sales-documents' AND has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can view sale docs" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'sales-documents' AND has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can delete sale docs" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'sales-documents' AND has_role(auth.uid(), 'admin'::app_role));
