-- ============================================================
-- Simply Imóveis - Core Bootstrap SQL (determinístico + idempotente)
-- Ordem: extensões -> tipos -> tabelas -> funções -> seeds -> triggers
--        -> RLS -> policies -> grants -> validação final
-- ============================================================

BEGIN;

-- ============================================================
-- 1) Extensões / Schemas
-- ============================================================
CREATE SCHEMA IF NOT EXISTS public;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- 2) Tipos customizados
-- ============================================================
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='public' AND t.typname='property_type') THEN
    CREATE TYPE public.property_type AS ENUM ('Apartamento', 'Casa', 'Cobertura', 'Terreno', 'Sala Comercial');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='public' AND t.typname='property_status') THEN
    CREATE TYPE public.property_status AS ENUM ('venda', 'aluguel');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='public' AND t.typname='contract_status') THEN
    CREATE TYPE public.contract_status AS ENUM ('ativo', 'encerrado', 'cancelado', 'pendente');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='public' AND t.typname='document_type') THEN
    CREATE TYPE public.document_type AS ENUM ('contrato', 'foto', 'documento', 'laudo', 'comprovante', 'outro');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='public' AND t.typname='invoice_status') THEN
    CREATE TYPE public.invoice_status AS ENUM ('pendente', 'pago', 'atrasado', 'cancelado');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='public' AND t.typname='lead_source') THEN
    CREATE TYPE public.lead_source AS ENUM ('site', 'whatsapp', 'indicacao', 'portal', 'placa', 'telefone', 'chat', 'outro');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='public' AND t.typname='lead_status') THEN
    CREATE TYPE public.lead_status AS ENUM ('novo', 'contato_feito', 'visita_agendada', 'proposta', 'negociacao', 'fechado_ganho', 'fechado_perdido');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='public' AND t.typname='transaction_category') THEN
    CREATE TYPE public.transaction_category AS ENUM ('aluguel', 'venda', 'comissao', 'manutencao', 'condominio', 'iptu', 'seguro', 'taxa_administracao', 'reparo', 'outro');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='public' AND t.typname='transaction_type') THEN
    CREATE TYPE public.transaction_type AS ENUM ('receita', 'despesa');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='public' AND t.typname='app_role') THEN
    CREATE TYPE public.app_role AS ENUM ('admin', 'moderator', 'user');
  END IF;
END $$;

-- ============================================================
-- 3) Tabelas base (sem uso de dependências futuras)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.properties (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  title text NOT NULL,
  address text NOT NULL,
  neighborhood text,
  city text DEFAULT 'Fortaleza',
  description text,
  price numeric NOT NULL,
  bedrooms integer NOT NULL DEFAULT 0,
  suites integer NOT NULL DEFAULT 0,
  bathrooms integer NOT NULL DEFAULT 0,
  garage_spots integer NOT NULL DEFAULT 0,
  area numeric NOT NULL DEFAULT 0,
  pool_size numeric DEFAULT 0,
  type public.property_type NOT NULL DEFAULT 'Apartamento',
  status public.property_status NOT NULL DEFAULT 'venda',
  featured boolean NOT NULL DEFAULT false,
  active boolean NOT NULL DEFAULT true,
  nearby_points text,
  short_code text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.property_media (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  file_path text NOT NULL,
  file_type text NOT NULL,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.contact_submissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  email text NOT NULL,
  phone text,
  subject text,
  message text NOT NULL,
  chat_transcript text,
  visit_date text,
  source text DEFAULT 'form',
  read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  role public.app_role NOT NULL,
  UNIQUE(user_id, role)
);

CREATE TABLE IF NOT EXISTS public.leads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  name text NOT NULL,
  phone text,
  email text,
  source public.lead_source NOT NULL DEFAULT 'site',
  status public.lead_status NOT NULL DEFAULT 'novo',
  interest_type text,
  property_id uuid REFERENCES public.properties(id),
  budget_min numeric,
  budget_max numeric,
  assigned_to uuid,
  next_follow_up timestamptz,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.tenants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  name text NOT NULL,
  email text,
  phone text,
  cpf_cnpj text,
  rg text,
  address text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.rental_contracts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  property_id uuid REFERENCES public.properties(id),
  tenant_id uuid REFERENCES public.tenants(id),
  start_date date NOT NULL,
  end_date date NOT NULL,
  monthly_rent numeric NOT NULL,
  deposit_amount numeric DEFAULT 0,
  payment_day integer NOT NULL DEFAULT 5,
  adjustment_index text DEFAULT 'IGPM',
  late_fee_percentage numeric DEFAULT 2,
  commission_rate numeric DEFAULT 10,
  commission_value numeric DEFAULT 0,
  status public.contract_status NOT NULL DEFAULT 'ativo',
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.sales (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  property_id uuid REFERENCES public.properties(id),
  lead_id uuid REFERENCES public.leads(id),
  buyer_name text,
  buyer_email text,
  buyer_phone text,
  buyer_cpf text,
  sale_value numeric,
  commission_rate numeric DEFAULT 5,
  commission_value numeric,
  proposal_date date,
  closing_date date,
  status text NOT NULL DEFAULT 'em_andamento',
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.financial_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  type public.transaction_type NOT NULL,
  category public.transaction_category NOT NULL DEFAULT 'outro',
  description text NOT NULL,
  amount numeric NOT NULL,
  date date NOT NULL DEFAULT CURRENT_DATE,
  due_date date,
  paid_date date,
  status public.invoice_status NOT NULL DEFAULT 'pendente',
  property_id uuid REFERENCES public.properties(id),
  contract_id uuid REFERENCES public.rental_contracts(id),
  tenant_id uuid REFERENCES public.tenants(id),
  payment_method text,
  receipt_path text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.property_inspections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  property_id uuid NOT NULL REFERENCES public.properties(id),
  tenant_id uuid REFERENCES public.tenants(id),
  contract_id uuid REFERENCES public.rental_contracts(id),
  inspection_type text NOT NULL DEFAULT 'entrada',
  inspection_date date NOT NULL DEFAULT CURRENT_DATE,
  status text NOT NULL DEFAULT 'pendente',
  inspector_name text,
  floor_condition text,
  painting_condition text,
  electrical_condition text,
  plumbing_condition text,
  rooms_condition text,
  keys_delivered integer DEFAULT 0,
  meter_reading_water text,
  meter_reading_electricity text,
  meter_reading_gas text,
  general_notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.inspection_media (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  inspection_id uuid NOT NULL REFERENCES public.property_inspections(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  file_path text NOT NULL,
  file_name text NOT NULL,
  file_type text NOT NULL,
  media_category text NOT NULL DEFAULT 'geral',
  notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.scheduled_visits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid REFERENCES public.properties(id),
  client_name text NOT NULL,
  client_phone text NOT NULL,
  client_email text,
  preferred_date text NOT NULL,
  preferred_time text NOT NULL,
  notes text,
  status text NOT NULL DEFAULT 'pendente',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.contract_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contract_id uuid REFERENCES public.rental_contracts(id),
  user_id uuid NOT NULL,
  file_name text NOT NULL,
  file_path text NOT NULL,
  file_type text NOT NULL,
  document_type public.document_type NOT NULL DEFAULT 'documento',
  notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.tenant_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id),
  user_id uuid NOT NULL,
  file_name text NOT NULL,
  file_path text NOT NULL,
  file_type text NOT NULL,
  document_type text NOT NULL DEFAULT 'documento',
  notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.sales_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_id uuid NOT NULL REFERENCES public.sales(id),
  user_id uuid NOT NULL,
  file_name text NOT NULL,
  file_path text NOT NULL,
  file_type text NOT NULL,
  document_type text NOT NULL DEFAULT 'documento',
  notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.property_code_sequences (
  prefix text PRIMARY KEY,
  last_number integer NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_user_roles_user_id ON public.user_roles(user_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_role ON public.user_roles(role);
CREATE INDEX IF NOT EXISTS idx_properties_active ON public.properties(active);
CREATE INDEX IF NOT EXISTS idx_properties_user_id ON public.properties(user_id);
CREATE INDEX IF NOT EXISTS idx_property_media_property_id ON public.property_media(property_id);
CREATE INDEX IF NOT EXISTS idx_leads_property_id ON public.leads(property_id);

-- ============================================================
-- 4) Funções auxiliares
-- ============================================================
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
  );
$$;

CREATE OR REPLACE FUNCTION public.has_role_text(_user_id uuid, _role text)
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
      AND role::text = _role
  );
$$;

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

-- ============================================================
-- 5) Validações defensivas (core)
-- ============================================================
DO $$
DECLARE
  missing_types text;
  missing_tables text;
  missing_functions text;
BEGIN
  WITH req(name) AS (
    SELECT unnest(ARRAY[
      'app_role','property_type','property_status','contract_status','document_type',
      'invoice_status','lead_source','lead_status','transaction_category','transaction_type'
    ]::text[])
  )
  SELECT string_agg(req.name, ', ') INTO missing_types
  FROM req
  LEFT JOIN pg_type t ON t.typname = req.name
  LEFT JOIN pg_namespace n ON n.oid = t.typnamespace AND n.nspname = 'public'
  WHERE n.oid IS NULL;

  IF missing_types IS NOT NULL THEN
    RAISE EXCEPTION 'Tipos ausentes antes das fases seguintes: %', missing_types;
  END IF;

  WITH req(name) AS (
    SELECT unnest(ARRAY[
      'properties','property_media','contact_submissions','user_roles','leads','tenants',
      'rental_contracts','sales','financial_transactions','property_inspections',
      'inspection_media','scheduled_visits','contract_documents','tenant_documents',
      'sales_documents','property_code_sequences'
    ]::text[])
  )
  SELECT string_agg(req.name, ', ') INTO missing_tables
  FROM req
  WHERE to_regclass('public.' || req.name) IS NULL;

  IF missing_tables IS NOT NULL THEN
    RAISE EXCEPTION 'Tabelas ausentes antes de RLS/policies: %', missing_tables;
  END IF;

  WITH req(sig) AS (
    SELECT unnest(ARRAY[
      'public.has_role(uuid,public.app_role)',
      'public.has_role_text(uuid,text)',
      'public.update_updated_at_column()',
      'public.generate_property_short_code()',
      'public.update_property_short_code_on_status_change()'
    ]::text[])
  )
  SELECT string_agg(req.sig, ', ') INTO missing_functions
  FROM req
  WHERE to_regprocedure(req.sig) IS NULL;

  IF missing_functions IS NOT NULL THEN
    RAISE EXCEPTION 'Funções ausentes antes de triggers/policies: %', missing_functions;
  END IF;
END
$$;

-- ============================================================
-- 6) Seeds mínimos
-- ============================================================
INSERT INTO public.property_code_sequences(prefix, last_number)
VALUES ('A', 0), ('V', 0)
ON CONFLICT (prefix) DO NOTHING;

-- ============================================================
-- 7) Triggers
-- ============================================================
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

DO $$
DECLARE
  tbl text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['properties','tenants','leads','rental_contracts','sales','property_inspections']
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS update_%1$s_updated_at ON public.%1$I', tbl);
    EXECUTE format(
      'CREATE TRIGGER update_%1$s_updated_at BEFORE UPDATE ON public.%1$I FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()',
      tbl
    );
  END LOOP;
END
$$;

-- ============================================================
-- 8) Habilitar RLS
-- ============================================================
DO $$
DECLARE
  tbl text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY[
    'properties','property_media','contact_submissions','user_roles','leads','tenants',
    'rental_contracts','sales','financial_transactions','property_inspections',
    'inspection_media','scheduled_visits','contract_documents','tenant_documents',
    'sales_documents','property_code_sequences'
  ]
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', tbl);
  END LOOP;
END
$$;

-- ============================================================
-- 9) Policies
-- ============================================================
-- Properties
DROP POLICY IF EXISTS "Admins can manage all properties" ON public.properties;
DROP POLICY IF EXISTS "Admins can manage properties" ON public.properties;
DROP POLICY IF EXISTS "Anyone can view active properties" ON public.properties;
DROP POLICY IF EXISTS "Users can insert own properties" ON public.properties;
DROP POLICY IF EXISTS "Users can update own properties" ON public.properties;
DROP POLICY IF EXISTS "Users can delete own properties" ON public.properties;
DROP POLICY IF EXISTS "Users can view own inactive properties" ON public.properties;

CREATE POLICY "Admins can manage properties" ON public.properties FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::public.app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));
CREATE POLICY "Anyone can view active properties" ON public.properties FOR SELECT TO public
  USING (active = true);
CREATE POLICY "Users can insert own properties" ON public.properties FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own properties" ON public.properties FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete own properties" ON public.properties FOR DELETE TO authenticated
  USING (auth.uid() = user_id);
CREATE POLICY "Users can view own inactive properties" ON public.properties FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

-- Property media
DROP POLICY IF EXISTS "Admins can insert property media" ON public.property_media;
DROP POLICY IF EXISTS "Admins can update property media" ON public.property_media;
DROP POLICY IF EXISTS "Admins can delete property media" ON public.property_media;
DROP POLICY IF EXISTS "Admins can manage property media" ON public.property_media;
DROP POLICY IF EXISTS "Anyone can view property media" ON public.property_media;
DROP POLICY IF EXISTS "Users can insert media for own properties" ON public.property_media;
DROP POLICY IF EXISTS "Users can update media for own properties" ON public.property_media;
DROP POLICY IF EXISTS "Users can delete media for own properties" ON public.property_media;

CREATE POLICY "Admins can manage property media" ON public.property_media FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::public.app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));
CREATE POLICY "Anyone can view property media" ON public.property_media FOR SELECT TO public USING (true);
CREATE POLICY "Users can insert media for own properties" ON public.property_media FOR INSERT TO authenticated
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.properties p
    WHERE p.id = property_media.property_id AND p.user_id = auth.uid()
  ));
CREATE POLICY "Users can update media for own properties" ON public.property_media FOR UPDATE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.properties p
    WHERE p.id = property_media.property_id AND p.user_id = auth.uid()
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.properties p
    WHERE p.id = property_media.property_id AND p.user_id = auth.uid()
  ));
CREATE POLICY "Users can delete media for own properties" ON public.property_media FOR DELETE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.properties p
    WHERE p.id = property_media.property_id AND p.user_id = auth.uid()
  ));

-- Contact submissions
DROP POLICY IF EXISTS "Anyone can submit contact" ON public.contact_submissions;
DROP POLICY IF EXISTS "Admins can view contacts" ON public.contact_submissions;
DROP POLICY IF EXISTS "Admins can update contacts" ON public.contact_submissions;
DROP POLICY IF EXISTS "Admins can delete contacts" ON public.contact_submissions;

CREATE POLICY "Anyone can submit contact" ON public.contact_submissions FOR INSERT TO public WITH CHECK (true);
CREATE POLICY "Admins can view contacts" ON public.contact_submissions FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::public.app_role));
CREATE POLICY "Admins can update contacts" ON public.contact_submissions FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::public.app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));
CREATE POLICY "Admins can delete contacts" ON public.contact_submissions FOR DELETE TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::public.app_role));

-- Scheduled visits
DROP POLICY IF EXISTS "Anyone can insert visits" ON public.scheduled_visits;
DROP POLICY IF EXISTS "Admins can view visits" ON public.scheduled_visits;
DROP POLICY IF EXISTS "Admins can update visits" ON public.scheduled_visits;
DROP POLICY IF EXISTS "Admins can delete visits" ON public.scheduled_visits;

CREATE POLICY "Anyone can insert visits" ON public.scheduled_visits FOR INSERT TO public WITH CHECK (true);
CREATE POLICY "Admins can view visits" ON public.scheduled_visits FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::public.app_role));
CREATE POLICY "Admins can update visits" ON public.scheduled_visits FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::public.app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));
CREATE POLICY "Admins can delete visits" ON public.scheduled_visits FOR DELETE TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::public.app_role));

-- Admin-only business tables
DROP POLICY IF EXISTS "Admins can manage leads" ON public.leads;
CREATE POLICY "Admins can manage leads" ON public.leads FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::public.app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Admins can manage tenants" ON public.tenants;
CREATE POLICY "Admins can manage tenants" ON public.tenants FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::public.app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Admins can manage contracts" ON public.rental_contracts;
CREATE POLICY "Admins can manage contracts" ON public.rental_contracts FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::public.app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Admins can manage sales" ON public.sales;
CREATE POLICY "Admins can manage sales" ON public.sales FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::public.app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Admins can manage transactions" ON public.financial_transactions;
CREATE POLICY "Admins can manage transactions" ON public.financial_transactions FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::public.app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Admins can manage inspections" ON public.property_inspections;
CREATE POLICY "Admins can manage inspections" ON public.property_inspections FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::public.app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Admins can manage inspection media" ON public.inspection_media;
CREATE POLICY "Admins can manage inspection media" ON public.inspection_media FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::public.app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Admins can manage documents" ON public.contract_documents;
CREATE POLICY "Admins can manage documents" ON public.contract_documents FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::public.app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Admins can manage tenant docs" ON public.tenant_documents;
CREATE POLICY "Admins can manage tenant docs" ON public.tenant_documents FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::public.app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Admins can manage sale docs" ON public.sales_documents;
CREATE POLICY "Admins can manage sale docs" ON public.sales_documents FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::public.app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Admins can manage property code sequences" ON public.property_code_sequences;
DROP POLICY IF EXISTS "Admins can manage code sequences" ON public.property_code_sequences;
CREATE POLICY "Admins can manage code sequences" ON public.property_code_sequences FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::public.app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

-- User roles table
DROP POLICY IF EXISTS "Admins can view roles" ON public.user_roles;
DROP POLICY IF EXISTS "Admins can insert roles" ON public.user_roles;
DROP POLICY IF EXISTS "Admins can update roles" ON public.user_roles;
DROP POLICY IF EXISTS "Admins can delete roles" ON public.user_roles;
DROP POLICY IF EXISTS "Users can view own role" ON public.user_roles;

CREATE POLICY "Admins can view roles" ON public.user_roles FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::public.app_role));
CREATE POLICY "Admins can insert roles" ON public.user_roles FOR INSERT TO authenticated
  WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));
CREATE POLICY "Admins can update roles" ON public.user_roles FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::public.app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));
CREATE POLICY "Admins can delete roles" ON public.user_roles FOR DELETE TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::public.app_role));
CREATE POLICY "Users can view own role" ON public.user_roles FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

-- ============================================================
-- 10) Grants
-- ============================================================
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role, authenticator;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role)
TO anon, authenticated, service_role, authenticator;
GRANT EXECUTE ON FUNCTION public.has_role_text(uuid, text)
TO anon, authenticated, service_role, authenticator;

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
  GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
  GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;

-- ============================================================
-- 11) Validação final
-- ============================================================
DO $$
DECLARE
  missing_rls text;
BEGIN
  WITH req(tbl) AS (
    SELECT unnest(ARRAY[
      'properties','property_media','contact_submissions','user_roles','leads','tenants',
      'rental_contracts','sales','financial_transactions','property_inspections',
      'inspection_media','scheduled_visits','contract_documents','tenant_documents',
      'sales_documents','property_code_sequences'
    ]::text[])
  )
  SELECT string_agg(req.tbl, ', ') INTO missing_rls
  FROM req
  LEFT JOIN pg_tables t ON t.schemaname='public' AND t.tablename=req.tbl
  WHERE t.rowsecurity IS DISTINCT FROM true;

  IF missing_rls IS NOT NULL THEN
    RAISE EXCEPTION 'RLS não habilitado em: %', missing_rls;
  END IF;
END
$$;

COMMIT;
