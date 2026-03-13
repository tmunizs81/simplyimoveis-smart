-- Create property type enum
CREATE TYPE public.property_type AS ENUM ('Apartamento', 'Casa', 'Cobertura', 'Terreno', 'Sala Comercial');
CREATE TYPE public.property_status AS ENUM ('venda', 'aluguel');

-- Create properties table
CREATE TABLE public.properties (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  address TEXT NOT NULL,
  description TEXT,
  price NUMERIC(12,2) NOT NULL,
  bedrooms INTEGER NOT NULL DEFAULT 0,
  bathrooms INTEGER NOT NULL DEFAULT 0,
  area NUMERIC(10,2) NOT NULL DEFAULT 0,
  type property_type NOT NULL DEFAULT 'Apartamento',
  status property_status NOT NULL DEFAULT 'venda',
  featured BOOLEAN NOT NULL DEFAULT false,
  active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create property_media table for photos and videos
CREATE TABLE public.property_media (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  file_path TEXT NOT NULL,
  file_type TEXT NOT NULL CHECK (file_type IN ('image', 'video')),
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.properties ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.property_media ENABLE ROW LEVEL SECURITY;

-- Properties: anyone can view active properties
CREATE POLICY "Anyone can view active properties"
  ON public.properties FOR SELECT
  USING (active = true);

-- Properties: authenticated users can manage their own
CREATE POLICY "Users can insert own properties"
  ON public.properties FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own properties"
  ON public.properties FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own properties"
  ON public.properties FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- Users can also see their own inactive properties
CREATE POLICY "Users can view own inactive properties"
  ON public.properties FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- Property media: anyone can view
CREATE POLICY "Anyone can view property media"
  ON public.property_media FOR SELECT
  USING (true);

-- Property media: authenticated users can manage media for their own properties
CREATE POLICY "Users can insert media for own properties"
  ON public.property_media FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.properties
      WHERE id = property_id AND user_id = auth.uid()
    )
  );

CREATE POLICY "Users can delete media for own properties"
  ON public.property_media FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.properties
      WHERE id = property_id AND user_id = auth.uid()
    )
  );

-- Updated_at trigger
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

CREATE TRIGGER update_properties_updated_at
  BEFORE UPDATE ON public.properties
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Storage bucket for property media
INSERT INTO storage.buckets (id, name, public)
VALUES ('property-media', 'property-media', true);

-- Storage policies
CREATE POLICY "Property media is publicly accessible"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'property-media');

CREATE POLICY "Authenticated users can upload property media"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'property-media');

CREATE POLICY "Authenticated users can update own property media"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (bucket_id = 'property-media');

CREATE POLICY "Authenticated users can delete own property media"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (bucket_id = 'property-media');