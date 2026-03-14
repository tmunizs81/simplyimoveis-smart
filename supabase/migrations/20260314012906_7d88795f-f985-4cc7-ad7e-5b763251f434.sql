
ALTER TABLE public.properties 
ADD COLUMN IF NOT EXISTS pool_size numeric DEFAULT 0,
ADD COLUMN IF NOT EXISTS nearby_points text;
