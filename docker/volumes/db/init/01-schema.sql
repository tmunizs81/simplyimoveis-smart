-- ============================================================
-- Simply Imóveis - Schema inicial
-- ============================================================

-- Enums
CREATE TYPE public.property_type AS ENUM ('Apartamento', 'Casa', 'Cobertura', 'Terreno', 'Sala Comercial');
CREATE TYPE public.property_status AS ENUM ('venda', 'aluguel');
CREATE TYPE public.contract_status AS ENUM ('ativo', 'encerrado', 'cancelado', 'pendente');
CREATE TYPE public.document_type AS ENUM ('contrato', 'foto', 'documento', 'laudo', 'comprovante', 'outro');
CREATE TYPE public.invoice_status AS ENUM ('pendente', 'pago', 'atrasado', 'cancelado');
CREATE TYPE public.lead_source AS ENUM ('site', 'whatsapp', 'indicacao', 'portal', 'placa', 'telefone', 'chat', 'outro');
CREATE TYPE public.lead_status AS ENUM ('novo', 'contato_feito', 'visita_agendada', 'proposta', 'negociacao', 'fechado_ganho', 'fechado_perdido');
CREATE TYPE public.transaction_category AS ENUM ('aluguel', 'venda', 'comissao', 'manutencao', 'condominio', 'iptu', 'seguro', 'taxa_administracao', 'reparo', 'outro');
CREATE TYPE public.transaction_type AS ENUM ('receita', 'despesa');
CREATE TYPE public.app_role AS ENUM ('admin', 'moderator', 'user');

-- ============================================================
-- Auth helper functions (necessárias para políticas RLS)
-- ============================================================
CREATE SCHEMA IF NOT EXISTS auth;

CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid,
    NULLIF((NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'), '')::uuid
  );
$$;

CREATE OR REPLACE FUNCTION auth.role()
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claim.role', true), '')::text,
    NULLIF((NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'), '')::text
  );
$$;

CREATE OR REPLACE FUNCTION auth.email()
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claim.email', true), '')::text,
    NULLIF((NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email'), '')::text
  );
$$;

-- ============================================================
-- Properties
-- ============================================================
CREATE TABLE public.properties (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  title text NOT NULL,
  address text NOT NULL,
  neighborhood text DEFAULT NULL,
  city text DEFAULT 'Fortaleza',
  description text,
  price numeric NOT NULL,
  bedrooms integer NOT NULL DEFAULT 0,
  suites integer NOT NULL DEFAULT 0,
  bathrooms integer NOT NULL DEFAULT 0,
  garage_spots integer NOT NULL DEFAULT 0,
  area numeric NOT NULL DEFAULT 0,
  pool_size numeric DEFAULT 0,
  type property_type NOT NULL DEFAULT 'Apartamento',
  status property_status NOT NULL DEFAULT 'venda',
  featured boolean NOT NULL DEFAULT false,
  active boolean NOT NULL DEFAULT true,
  nearby_points text,
  short_code text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.properties ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can view active properties" ON public.properties FOR SELECT USING (active = true);
CREATE POLICY "Users can insert own properties" ON public.properties FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own properties" ON public.properties FOR UPDATE TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Users can delete own properties" ON public.properties FOR DELETE TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Users can view own inactive properties" ON public.properties FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- ============================================================
-- Property Media
-- ============================================================
CREATE TABLE public.property_media (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  file_path text NOT NULL,
  file_type text NOT NULL,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.property_media ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can view property media" ON public.property_media FOR SELECT USING (true);
CREATE POLICY "Users can insert media for own properties" ON public.property_media FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM properties WHERE properties.id = property_media.property_id AND properties.user_id = auth.uid()));
CREATE POLICY "Users can update media for own properties" ON public.property_media FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM properties WHERE properties.id = property_media.property_id AND properties.user_id = auth.uid()));
CREATE POLICY "Users can delete media for own properties" ON public.property_media FOR DELETE TO authenticated USING (EXISTS (SELECT 1 FROM properties WHERE properties.id = property_media.property_id AND properties.user_id = auth.uid()));

-- ============================================================
-- Contact Submissions
-- ============================================================
CREATE TABLE public.contact_submissions (
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

ALTER TABLE public.contact_submissions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can submit contact" ON public.contact_submissions FOR INSERT WITH CHECK (true);

-- ============================================================
-- User Roles
-- ============================================================
CREATE TABLE public.user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  role app_role NOT NULL,
  UNIQUE(user_id, role)
);

ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- has_role function
-- ============================================================
CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role app_role)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role)
$$;

-- Admin RLS policies using has_role
CREATE POLICY "Admins can manage all properties" ON public.properties FOR ALL TO authenticated
  USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can insert property media" ON public.property_media FOR INSERT TO authenticated
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));
CREATE POLICY "Admins can update property media" ON public.property_media FOR UPDATE TO authenticated
  USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));
CREATE POLICY "Admins can delete property media" ON public.property_media FOR DELETE TO authenticated
  USING (has_role(auth.uid(), 'admin'::app_role));


CREATE POLICY "Admins can view roles" ON public.user_roles FOR SELECT TO authenticated
  USING (has_role(auth.uid(), 'admin'::app_role));
CREATE POLICY "Admins can insert roles" ON public.user_roles FOR INSERT TO authenticated
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));
CREATE POLICY "Admins can update roles" ON public.user_roles FOR UPDATE TO authenticated
  USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));
CREATE POLICY "Admins can delete roles" ON public.user_roles FOR DELETE TO authenticated
  USING (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can view contacts" ON public.contact_submissions FOR SELECT TO authenticated USING (has_role(auth.uid(), 'admin'::app_role));
CREATE POLICY "Admins can update contacts" ON public.contact_submissions FOR UPDATE TO authenticated USING (has_role(auth.uid(), 'admin'::app_role));
CREATE POLICY "Admins can delete contacts" ON public.contact_submissions FOR DELETE TO authenticated USING (has_role(auth.uid(), 'admin'::app_role));

-- ============================================================
-- Leads
-- ============================================================
CREATE TABLE public.leads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  name text NOT NULL,
  phone text,
  email text,
  source lead_source NOT NULL DEFAULT 'site',
  status lead_status NOT NULL DEFAULT 'novo',
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

ALTER TABLE public.leads ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins can manage leads" ON public.leads FOR ALL TO authenticated
  USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

-- ============================================================
-- Tenants
-- ============================================================
CREATE TABLE public.tenants (
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

ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins can manage tenants" ON public.tenants FOR ALL TO authenticated
  USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

-- ============================================================
-- Rental Contracts
-- ============================================================
CREATE TABLE public.rental_contracts (
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
  status contract_status NOT NULL DEFAULT 'ativo',
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.rental_contracts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins can manage contracts" ON public.rental_contracts FOR ALL TO authenticated
  USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

-- ============================================================
-- Sales
-- ============================================================
CREATE TABLE public.sales (
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

ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins can manage sales" ON public.sales FOR ALL TO authenticated
  USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

-- ============================================================
-- Financial Transactions
-- ============================================================
CREATE TABLE public.financial_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  type transaction_type NOT NULL,
  category transaction_category NOT NULL DEFAULT 'outro',
  description text NOT NULL,
  amount numeric NOT NULL,
  date date NOT NULL DEFAULT CURRENT_DATE,
  due_date date,
  paid_date date,
  status invoice_status NOT NULL DEFAULT 'pendente',
  property_id uuid REFERENCES public.properties(id),
  contract_id uuid REFERENCES public.rental_contracts(id),
  tenant_id uuid REFERENCES public.tenants(id),
  payment_method text,
  receipt_path text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.financial_transactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins can manage transactions" ON public.financial_transactions FOR ALL TO authenticated
  USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

-- ============================================================
-- Property Inspections
-- ============================================================
CREATE TABLE public.property_inspections (
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

ALTER TABLE public.property_inspections ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins can manage inspections" ON public.property_inspections FOR ALL TO authenticated
  USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

-- ============================================================
-- Inspection Media
-- ============================================================
CREATE TABLE public.inspection_media (
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

ALTER TABLE public.inspection_media ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins can manage inspection media" ON public.inspection_media FOR ALL TO authenticated
  USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

-- ============================================================
-- Scheduled Visits
-- ============================================================
CREATE TABLE public.scheduled_visits (
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

ALTER TABLE public.scheduled_visits ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can insert visits" ON public.scheduled_visits FOR INSERT WITH CHECK (true);
CREATE POLICY "Admins can view visits" ON public.scheduled_visits FOR SELECT TO authenticated USING (has_role(auth.uid(), 'admin'));
CREATE POLICY "Admins can update visits" ON public.scheduled_visits FOR UPDATE TO authenticated USING (has_role(auth.uid(), 'admin'));
CREATE POLICY "Admins can delete visits" ON public.scheduled_visits FOR DELETE TO authenticated USING (has_role(auth.uid(), 'admin'));

-- ============================================================
-- Document tables
-- ============================================================
CREATE TABLE public.contract_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contract_id uuid REFERENCES public.rental_contracts(id),
  user_id uuid NOT NULL,
  file_name text NOT NULL,
  file_path text NOT NULL,
  file_type text NOT NULL,
  document_type document_type NOT NULL DEFAULT 'documento',
  notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.contract_documents ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins can manage documents" ON public.contract_documents FOR ALL TO authenticated USING (has_role(auth.uid(), 'admin'));

CREATE TABLE public.tenant_documents (
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
ALTER TABLE public.tenant_documents ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins can manage tenant docs" ON public.tenant_documents FOR ALL TO authenticated USING (has_role(auth.uid(), 'admin'));

CREATE TABLE public.sales_documents (
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
ALTER TABLE public.sales_documents ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins can manage sale docs" ON public.sales_documents FOR ALL TO authenticated USING (has_role(auth.uid(), 'admin'));

-- ============================================================
-- Property Code Sequences
-- ============================================================
CREATE TABLE public.property_code_sequences (
  prefix text PRIMARY KEY,
  last_number integer NOT NULL DEFAULT 0
);
ALTER TABLE public.property_code_sequences ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins can manage property code sequences" ON public.property_code_sequences FOR ALL TO authenticated
  USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));
INSERT INTO public.property_code_sequences (prefix) VALUES ('A'), ('V');

-- ============================================================
-- Functions & Triggers
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS trigger LANGUAGE plpgsql SET search_path = 'public' AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

CREATE OR REPLACE FUNCTION public.generate_property_short_code()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public' AS $$
DECLARE v_prefix text; v_next_num integer;
BEGIN
  IF NEW.status = 'aluguel' THEN v_prefix := 'A'; ELSE v_prefix := 'V'; END IF;
  UPDATE public.property_code_sequences SET last_number = last_number + 1 WHERE prefix = v_prefix RETURNING last_number INTO v_next_num;
  NEW.short_code := v_prefix || '-' || lpad(v_next_num::text, 4, '0');
  RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION public.update_property_short_code_on_status_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public' AS $$
DECLARE v_prefix text; v_next_num integer;
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    IF NEW.status = 'aluguel' THEN v_prefix := 'A'; ELSE v_prefix := 'V'; END IF;
    UPDATE public.property_code_sequences SET last_number = last_number + 1 WHERE prefix = v_prefix RETURNING last_number INTO v_next_num;
    NEW.short_code := v_prefix || '-' || lpad(v_next_num::text, 4, '0');
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER set_short_code BEFORE INSERT ON public.properties FOR EACH ROW EXECUTE FUNCTION generate_property_short_code();
CREATE TRIGGER update_short_code BEFORE UPDATE ON public.properties FOR EACH ROW EXECUTE FUNCTION update_property_short_code_on_status_change();

-- ============================================================
-- Storage buckets (somente se schema storage já existir)
-- ============================================================
DO $$
BEGIN
  IF to_regclass('storage.buckets') IS NOT NULL THEN
    INSERT INTO storage.buckets (id, name, public) VALUES
      ('property-media', 'property-media', true),
      ('contract-documents', 'contract-documents', false),
      ('tenant-documents', 'tenant-documents', false),
      ('inspection-media', 'inspection-media', false),
      ('sales-documents', 'sales-documents', false)
    ON CONFLICT (id) DO NOTHING;
  END IF;
END $$;

-- ============================================================
-- Grants padrão do schema public (RLS controla acesso por linha)
-- ============================================================
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
  GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
  GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;
