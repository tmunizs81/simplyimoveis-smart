
CREATE POLICY "Authenticated users can delete contacts" ON public.contact_submissions
  FOR DELETE TO authenticated USING (true);
