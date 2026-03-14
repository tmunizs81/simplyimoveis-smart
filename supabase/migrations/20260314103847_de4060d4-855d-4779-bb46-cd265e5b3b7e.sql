
-- Add short_code column
ALTER TABLE public.properties ADD COLUMN short_code text UNIQUE;

-- Create sequence table
CREATE TABLE public.property_code_sequences (
  prefix text PRIMARY KEY,
  last_number integer NOT NULL DEFAULT 0
);

-- Initialize
INSERT INTO public.property_code_sequences (prefix, last_number) VALUES ('A', 0), ('V', 0);

-- Trigger function for INSERT
CREATE OR REPLACE FUNCTION public.generate_property_short_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prefix text;
  v_next_num integer;
BEGIN
  IF NEW.status = 'aluguel' THEN
    v_prefix := 'A';
  ELSE
    v_prefix := 'V';
  END IF;

  UPDATE public.property_code_sequences
  SET last_number = last_number + 1
  WHERE property_code_sequences.prefix = v_prefix
  RETURNING last_number INTO v_next_num;

  NEW.short_code := v_prefix || '-' || lpad(v_next_num::text, 4, '0');
  RETURN NEW;
END;
$$;

CREATE TRIGGER set_property_short_code
  BEFORE INSERT ON public.properties
  FOR EACH ROW
  WHEN (NEW.short_code IS NULL)
  EXECUTE FUNCTION public.generate_property_short_code();

-- Trigger function for status change on UPDATE
CREATE OR REPLACE FUNCTION public.update_property_short_code_on_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prefix text;
  v_next_num integer;
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    IF NEW.status = 'aluguel' THEN
      v_prefix := 'A';
    ELSE
      v_prefix := 'V';
    END IF;

    UPDATE public.property_code_sequences
    SET last_number = last_number + 1
    WHERE property_code_sequences.prefix = v_prefix
    RETURNING last_number INTO v_next_num;

    NEW.short_code := v_prefix || '-' || lpad(v_next_num::text, 4, '0');
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER update_property_short_code_on_status
  BEFORE UPDATE ON public.properties
  FOR EACH ROW
  EXECUTE FUNCTION public.update_property_short_code_on_status_change();

-- Backfill existing properties
DO $$
DECLARE
  prop RECORD;
  v_prefix text;
  v_next_num integer;
BEGIN
  FOR prop IN SELECT id, status FROM public.properties WHERE short_code IS NULL ORDER BY created_at LOOP
    IF prop.status = 'aluguel' THEN
      v_prefix := 'A';
    ELSE
      v_prefix := 'V';
    END IF;
    
    UPDATE public.property_code_sequences
    SET last_number = last_number + 1
    WHERE property_code_sequences.prefix = v_prefix
    RETURNING last_number INTO v_next_num;
    
    UPDATE public.properties
    SET short_code = v_prefix || '-' || lpad(v_next_num::text, 4, '0')
    WHERE id = prop.id;
  END LOOP;
END;
$$;
