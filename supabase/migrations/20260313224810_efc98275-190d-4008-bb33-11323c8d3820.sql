
CREATE TABLE public.scheduled_visits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid REFERENCES public.properties(id) ON DELETE CASCADE,
  client_name text NOT NULL,
  client_phone text NOT NULL,
  client_email text,
  preferred_date text NOT NULL,
  preferred_time text NOT NULL,
  notes text,
  status text NOT NULL DEFAULT 'pendente',
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.scheduled_visits ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can insert visits" ON public.scheduled_visits
  FOR INSERT TO public WITH CHECK (true);

CREATE POLICY "Authenticated users can view visits" ON public.scheduled_visits
  FOR SELECT TO authenticated USING (true);
