
CREATE TABLE public.contact_submissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  email text NOT NULL,
  phone text,
  subject text,
  message text NOT NULL,
  read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.contact_submissions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can submit contact" ON public.contact_submissions
  FOR INSERT TO public WITH CHECK (true);

CREATE POLICY "Authenticated users can view contacts" ON public.contact_submissions
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Authenticated users can update contacts" ON public.contact_submissions
  FOR UPDATE TO authenticated USING (true);
