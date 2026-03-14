
-- =============================================
-- REAL ESTATE MANAGEMENT SYSTEM - COMPLETE SCHEMA
-- =============================================

-- Enums
CREATE TYPE public.lead_status AS ENUM ('novo', 'contato_feito', 'visita_agendada', 'proposta', 'negociacao', 'fechado_ganho', 'fechado_perdido');
CREATE TYPE public.lead_source AS ENUM ('site', 'whatsapp', 'indicacao', 'portal', 'placa', 'telefone', 'chat', 'outro');
CREATE TYPE public.contract_status AS ENUM ('ativo', 'encerrado', 'cancelado', 'pendente');
CREATE TYPE public.transaction_type AS ENUM ('receita', 'despesa');
CREATE TYPE public.transaction_category AS ENUM ('aluguel', 'venda', 'comissao', 'manutencao', 'condominio', 'iptu', 'seguro', 'taxa_administracao', 'reparo', 'outro');
CREATE TYPE public.invoice_status AS ENUM ('pendente', 'pago', 'atrasado', 'cancelado');
CREATE TYPE public.document_type AS ENUM ('contrato', 'foto', 'documento', 'laudo', 'comprovante', 'outro');

-- =============================================
-- 1. TENANTS (Inquilinos / Clientes)
-- =============================================
CREATE TABLE public.tenants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  email text,
  phone text,
  cpf_cnpj text,
  rg text,
  address text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  user_id uuid NOT NULL
);

ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage tenants" ON public.tenants
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

-- =============================================
-- 2. LEADS (Prospects de Venda/Aluguel)
-- =============================================
CREATE TABLE public.leads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  email text,
  phone text,
  source lead_source NOT NULL DEFAULT 'site',
  status lead_status NOT NULL DEFAULT 'novo',
  property_id uuid REFERENCES public.properties(id) ON DELETE SET NULL,
  interest_type text, -- venda ou aluguel
  budget_min numeric,
  budget_max numeric,
  notes text,
  next_follow_up timestamptz,
  assigned_to uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  user_id uuid NOT NULL
);

ALTER TABLE public.leads ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage leads" ON public.leads
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

-- =============================================
-- 3. RENTAL CONTRACTS (Contratos de Aluguel)
-- =============================================
CREATE TABLE public.rental_contracts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid REFERENCES public.properties(id) ON DELETE SET NULL,
  tenant_id uuid REFERENCES public.tenants(id) ON DELETE SET NULL,
  start_date date NOT NULL,
  end_date date NOT NULL,
  monthly_rent numeric NOT NULL,
  deposit_amount numeric DEFAULT 0,
  payment_day integer NOT NULL DEFAULT 5,
  status contract_status NOT NULL DEFAULT 'ativo',
  notes text,
  late_fee_percentage numeric DEFAULT 2,
  adjustment_index text DEFAULT 'IGPM',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  user_id uuid NOT NULL
);

ALTER TABLE public.rental_contracts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage contracts" ON public.rental_contracts
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

-- =============================================
-- 4. CONTRACT DOCUMENTS (Documentos de Contratos)
-- =============================================
CREATE TABLE public.contract_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contract_id uuid REFERENCES public.rental_contracts(id) ON DELETE CASCADE,
  file_path text NOT NULL,
  file_name text NOT NULL,
  file_type text NOT NULL,
  document_type document_type NOT NULL DEFAULT 'documento',
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  user_id uuid NOT NULL
);

ALTER TABLE public.contract_documents ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage documents" ON public.contract_documents
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

-- =============================================
-- 5. FINANCIAL TRANSACTIONS
-- =============================================
CREATE TABLE public.financial_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type transaction_type NOT NULL,
  category transaction_category NOT NULL DEFAULT 'outro',
  description text NOT NULL,
  amount numeric NOT NULL,
  date date NOT NULL DEFAULT CURRENT_DATE,
  property_id uuid REFERENCES public.properties(id) ON DELETE SET NULL,
  contract_id uuid REFERENCES public.rental_contracts(id) ON DELETE SET NULL,
  tenant_id uuid REFERENCES public.tenants(id) ON DELETE SET NULL,
  status invoice_status NOT NULL DEFAULT 'pendente',
  due_date date,
  paid_date date,
  payment_method text,
  receipt_path text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  user_id uuid NOT NULL
);

ALTER TABLE public.financial_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage transactions" ON public.financial_transactions
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

-- =============================================
-- 6. SALES PIPELINE (Vendas)
-- =============================================
CREATE TABLE public.sales (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid REFERENCES public.properties(id) ON DELETE SET NULL,
  lead_id uuid REFERENCES public.leads(id) ON DELETE SET NULL,
  buyer_name text,
  buyer_email text,
  buyer_phone text,
  buyer_cpf text,
  sale_value numeric,
  commission_rate numeric DEFAULT 5,
  commission_value numeric,
  status text NOT NULL DEFAULT 'em_andamento',
  proposal_date date,
  closing_date date,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  user_id uuid NOT NULL
);

ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage sales" ON public.sales
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

-- =============================================
-- STORAGE BUCKET for contract documents
-- =============================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('contract-documents', 'contract-documents', false)
ON CONFLICT (id) DO NOTHING;

-- Storage policies for contract documents
CREATE POLICY "Admins can upload contract docs"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'contract-documents'
  AND public.has_role(auth.uid(), 'admin')
);

CREATE POLICY "Admins can view contract docs"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'contract-documents'
  AND public.has_role(auth.uid(), 'admin')
);

CREATE POLICY "Admins can delete contract docs"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'contract-documents'
  AND public.has_role(auth.uid(), 'admin')
);

-- =============================================
-- TRIGGERS for updated_at
-- =============================================
CREATE TRIGGER update_tenants_updated_at BEFORE UPDATE ON public.tenants
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_leads_updated_at BEFORE UPDATE ON public.leads
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_rental_contracts_updated_at BEFORE UPDATE ON public.rental_contracts
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_sales_updated_at BEFORE UPDATE ON public.sales
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
