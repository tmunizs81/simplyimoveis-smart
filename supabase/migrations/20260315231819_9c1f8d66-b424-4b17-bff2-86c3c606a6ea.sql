
-- Create triggers for property short_code generation (missing in Cloud)
DROP TRIGGER IF EXISTS set_short_code ON public.properties;
CREATE TRIGGER set_short_code
BEFORE INSERT ON public.properties
FOR EACH ROW
EXECUTE FUNCTION public.generate_property_short_code();

DROP TRIGGER IF EXISTS update_short_code ON public.properties;
CREATE TRIGGER update_short_code
BEFORE UPDATE ON public.properties
FOR EACH ROW
EXECUTE FUNCTION public.update_property_short_code_on_status_change();

-- Seed property_code_sequences if empty
INSERT INTO public.property_code_sequences(prefix, last_number)
VALUES ('A', 0), ('V', 0)
ON CONFLICT (prefix) DO NOTHING;
