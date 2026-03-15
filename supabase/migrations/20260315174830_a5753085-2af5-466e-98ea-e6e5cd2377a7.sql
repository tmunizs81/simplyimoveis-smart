-- Add admin policies for properties table (missing)
CREATE POLICY "Admins can manage properties"
ON public.properties
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::app_role))
WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));

-- Add admin policies for property_media table (missing)
CREATE POLICY "Admins can manage property media"
ON public.property_media
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::app_role))
WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));

-- Add admin policy for property_code_sequences (needed for trigger)
CREATE POLICY "Admins can manage code sequences"
ON public.property_code_sequences
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::app_role))
WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));