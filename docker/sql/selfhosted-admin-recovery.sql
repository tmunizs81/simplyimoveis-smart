-- ============================================================
-- Simply Imóveis - Recovery SQL (self-hosted VPS)
-- Idempotente: pode ser executado mais de uma vez
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1) Enum e tabela de roles
-- ------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON t.typnamespace = n.oid WHERE t.typname = 'app_role' AND n.nspname = 'public') THEN
    CREATE TYPE public.app_role AS ENUM ('admin', 'moderator', 'user');
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS public.user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  role public.app_role NOT NULL,
  UNIQUE (user_id, role)
);

ALTER TABLE public.user_roles
  ALTER COLUMN user_id SET NOT NULL,
  ALTER COLUMN role SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_user_roles_user_id ON public.user_roles(user_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_role ON public.user_roles(role);

-- ------------------------------------------------------------
-- 2) Função de autorização segura (sem recursão de RLS)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role public.app_role)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = _user_id
      AND role = _role
  )
$$;

GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role)
TO anon, authenticated, service_role, authenticator;

-- ------------------------------------------------------------
-- 3) Garantir RLS habilitado nas tabelas do admin
-- ------------------------------------------------------------
DO $$
DECLARE
  tbl text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY[
    'properties',
    'property_media',
    'property_code_sequences',
    'contact_submissions',
    'scheduled_visits',
    'leads',
    'tenants',
    'rental_contracts',
    'sales',
    'financial_transactions',
    'property_inspections',
    'inspection_media',
    'contract_documents',
    'tenant_documents',
    'sales_documents',
    'user_roles'
  ]
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', tbl);
  END LOOP;
END
$$;

-- ------------------------------------------------------------
-- 4) Policies de properties
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "Admins can manage all properties" ON public.properties;
DROP POLICY IF EXISTS "Admins can manage properties" ON public.properties;
CREATE POLICY "Admins can manage properties"
ON public.properties
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::public.app_role))
WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Anyone can view active properties" ON public.properties;
CREATE POLICY "Anyone can view active properties"
ON public.properties
FOR SELECT
TO public
USING (active = true);

DROP POLICY IF EXISTS "Users can insert own properties" ON public.properties;
CREATE POLICY "Users can insert own properties"
ON public.properties
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own properties" ON public.properties;
CREATE POLICY "Users can update own properties"
ON public.properties
FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own properties" ON public.properties;
CREATE POLICY "Users can delete own properties"
ON public.properties
FOR DELETE
TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view own inactive properties" ON public.properties;
CREATE POLICY "Users can view own inactive properties"
ON public.properties
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- ------------------------------------------------------------
-- 5) Policies de property_media
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "Admins can manage property media" ON public.property_media;
CREATE POLICY "Admins can manage property media"
ON public.property_media
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::public.app_role))
WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Anyone can view property media" ON public.property_media;
CREATE POLICY "Anyone can view property media"
ON public.property_media
FOR SELECT
TO public
USING (true);

DROP POLICY IF EXISTS "Users can insert media for own properties" ON public.property_media;
CREATE POLICY "Users can insert media for own properties"
ON public.property_media
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.properties p
    WHERE p.id = property_media.property_id
      AND p.user_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "Users can update media for own properties" ON public.property_media;
CREATE POLICY "Users can update media for own properties"
ON public.property_media
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.properties p
    WHERE p.id = property_media.property_id
      AND p.user_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.properties p
    WHERE p.id = property_media.property_id
      AND p.user_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "Users can delete media for own properties" ON public.property_media;
CREATE POLICY "Users can delete media for own properties"
ON public.property_media
FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.properties p
    WHERE p.id = property_media.property_id
      AND p.user_id = auth.uid()
  )
);

-- ------------------------------------------------------------
-- 6) Policies de tabelas admin (FOR ALL)
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "Admins can manage leads" ON public.leads;
CREATE POLICY "Admins can manage leads"
ON public.leads
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::public.app_role))
WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Admins can manage tenants" ON public.tenants;
CREATE POLICY "Admins can manage tenants"
ON public.tenants
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::public.app_role))
WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Admins can manage contracts" ON public.rental_contracts;
CREATE POLICY "Admins can manage contracts"
ON public.rental_contracts
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::public.app_role))
WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Admins can manage sales" ON public.sales;
CREATE POLICY "Admins can manage sales"
ON public.sales
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::public.app_role))
WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Admins can manage transactions" ON public.financial_transactions;
CREATE POLICY "Admins can manage transactions"
ON public.financial_transactions
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::public.app_role))
WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Admins can manage inspections" ON public.property_inspections;
CREATE POLICY "Admins can manage inspections"
ON public.property_inspections
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::public.app_role))
WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Admins can manage inspection media" ON public.inspection_media;
CREATE POLICY "Admins can manage inspection media"
ON public.inspection_media
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::public.app_role))
WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Admins can manage documents" ON public.contract_documents;
CREATE POLICY "Admins can manage documents"
ON public.contract_documents
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::public.app_role))
WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Admins can manage tenant docs" ON public.tenant_documents;
CREATE POLICY "Admins can manage tenant docs"
ON public.tenant_documents
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::public.app_role))
WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Admins can manage sale docs" ON public.sales_documents;
CREATE POLICY "Admins can manage sale docs"
ON public.sales_documents
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::public.app_role))
WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Admins can manage property code sequences" ON public.property_code_sequences;
DROP POLICY IF EXISTS "Admins can manage code sequences" ON public.property_code_sequences;
CREATE POLICY "Admins can manage code sequences"
ON public.property_code_sequences
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::public.app_role))
WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

-- ------------------------------------------------------------
-- 7) Policies públicas e de atendimento
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "Anyone can submit contact" ON public.contact_submissions;
CREATE POLICY "Anyone can submit contact"
ON public.contact_submissions
FOR INSERT
TO public
WITH CHECK (true);

DROP POLICY IF EXISTS "Admins can view contacts" ON public.contact_submissions;
CREATE POLICY "Admins can view contacts"
ON public.contact_submissions
FOR SELECT
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Admins can update contacts" ON public.contact_submissions;
CREATE POLICY "Admins can update contacts"
ON public.contact_submissions
FOR UPDATE
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::public.app_role))
WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Admins can delete contacts" ON public.contact_submissions;
CREATE POLICY "Admins can delete contacts"
ON public.contact_submissions
FOR DELETE
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Anyone can insert visits" ON public.scheduled_visits;
CREATE POLICY "Anyone can insert visits"
ON public.scheduled_visits
FOR INSERT
TO public
WITH CHECK (true);

DROP POLICY IF EXISTS "Admins can view visits" ON public.scheduled_visits;
CREATE POLICY "Admins can view visits"
ON public.scheduled_visits
FOR SELECT
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Admins can update visits" ON public.scheduled_visits;
CREATE POLICY "Admins can update visits"
ON public.scheduled_visits
FOR UPDATE
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::public.app_role))
WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Admins can delete visits" ON public.scheduled_visits;
CREATE POLICY "Admins can delete visits"
ON public.scheduled_visits
FOR DELETE
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::public.app_role));

-- ------------------------------------------------------------
-- 8) Policies de user_roles
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "Admins can view roles" ON public.user_roles;
DROP POLICY IF EXISTS "Admins can insert roles" ON public.user_roles;
DROP POLICY IF EXISTS "Admins can update roles" ON public.user_roles;
DROP POLICY IF EXISTS "Admins can delete roles" ON public.user_roles;
DROP POLICY IF EXISTS "Users can view own role" ON public.user_roles;

CREATE POLICY "Admins can view roles"
ON public.user_roles
FOR SELECT
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::public.app_role));

CREATE POLICY "Admins can insert roles"
ON public.user_roles
FOR INSERT
TO authenticated
WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

CREATE POLICY "Admins can update roles"
ON public.user_roles
FOR UPDATE
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::public.app_role))
WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

CREATE POLICY "Admins can delete roles"
ON public.user_roles
FOR DELETE
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::public.app_role));

CREATE POLICY "Users can view own role"
ON public.user_roles
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- ------------------------------------------------------------
-- 9) Funções e triggers auxiliares
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

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

  INSERT INTO public.property_code_sequences(prefix, last_number)
  VALUES (v_prefix, 0)
  ON CONFLICT (prefix) DO NOTHING;

  UPDATE public.property_code_sequences
  SET last_number = last_number + 1
  WHERE prefix = v_prefix
  RETURNING last_number INTO v_next_num;

  NEW.short_code := v_prefix || '-' || lpad(v_next_num::text, 4, '0');
  RETURN NEW;
END;
$$;

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

    INSERT INTO public.property_code_sequences(prefix, last_number)
    VALUES (v_prefix, 0)
    ON CONFLICT (prefix) DO NOTHING;

    UPDATE public.property_code_sequences
    SET last_number = last_number + 1
    WHERE prefix = v_prefix
    RETURNING last_number INTO v_next_num;

    NEW.short_code := v_prefix || '-' || lpad(v_next_num::text, 4, '0');
  END IF;

  RETURN NEW;
END;
$$;

INSERT INTO public.property_code_sequences(prefix, last_number)
VALUES ('A', 0), ('V', 0)
ON CONFLICT (prefix) DO NOTHING;

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

DROP TRIGGER IF EXISTS update_properties_updated_at ON public.properties;
CREATE TRIGGER update_properties_updated_at
BEFORE UPDATE ON public.properties
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_tenants_updated_at ON public.tenants;
CREATE TRIGGER update_tenants_updated_at
BEFORE UPDATE ON public.tenants
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_leads_updated_at ON public.leads;
CREATE TRIGGER update_leads_updated_at
BEFORE UPDATE ON public.leads
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_rental_contracts_updated_at ON public.rental_contracts;
CREATE TRIGGER update_rental_contracts_updated_at
BEFORE UPDATE ON public.rental_contracts
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_sales_updated_at ON public.sales;
CREATE TRIGGER update_sales_updated_at
BEFORE UPDATE ON public.sales
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_property_inspections_updated_at ON public.property_inspections;
CREATE TRIGGER update_property_inspections_updated_at
BEFORE UPDATE ON public.property_inspections
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- ------------------------------------------------------------
-- 10) Grants básicos
-- ------------------------------------------------------------
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role, authenticator;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
  GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
  GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;

COMMIT;
