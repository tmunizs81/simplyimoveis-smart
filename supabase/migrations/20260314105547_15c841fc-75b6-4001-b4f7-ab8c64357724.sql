
ALTER TABLE public.rental_contracts 
ADD COLUMN commission_rate numeric DEFAULT 10,
ADD COLUMN commission_value numeric DEFAULT 0;
