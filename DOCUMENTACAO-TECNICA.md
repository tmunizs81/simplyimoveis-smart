# Simply Imóveis — Documentação Técnica Completa (Export / Portabilidade)

> Documento gerado para permitir a recriação integral do SaaS em ambiente local (Claude Code / terminal) sem perda de regras de negócio, rotas ou esquema de banco.
> Ambiente-alvo de produção: **self-hosted Docker em VPS** (Supabase self-hosted: Postgres + GoTrue + PostgREST + Storage + Kong + Edge Runtime Deno). Não há dependência funcional obrigatória de Lovable Cloud.

---

# 1. Visão Geral da Arquitetura & Stack

## 1.1 Propósito central

Plataforma de imobiliária (Simply Imóveis, Fortaleza/CE — CRECI 29379) composta por:

1. **Site público (vitrine)** — captação de leads: home institucional, listagem de imóveis, página de detalhe com galeria/slideshow, página de serviços, chat com IA e botão WhatsApp.
2. **ERP imobiliário (`/admin`)** — gestão completa: imóveis + mídias, contatos, leads (funil Kanban), vendas, inquilinos, contratos de aluguel, vistorias, financeiro, relatórios, backup/restore, insights de IA, kit de marketing com IA e manual do sistema.

**Fluxo principal de valor:**
`Visitante → vê imóvel no site → envia contato/agenda visita (ou usa o chat IA) → registro em contact_submissions/scheduled_visits → notificação Telegram → admin converte em lead → lead vira venda ou contrato de aluguel → lançamentos financeiros, vistorias e documentos → relatórios e previsão de receita.`

## 1.2 Stack tecnológica

| Camada | Tecnologia |
|---|---|
| Build/Bundler | Vite 5 (`@vitejs/plugin-react-swc`), porta dev `8080` |
| Frontend | React 18.3 + TypeScript 5.8 (SPA, sem SSR) |
| Roteamento | `react-router-dom` 6.30 (`BrowserRouter`) |
| Estilização | Tailwind CSS 3.4 + `tailwindcss-animate` + `@tailwindcss/typography`; tokens semânticos em `src/index.css` e `tailwind.config.ts` |
| UI kit | shadcn/ui sobre Radix UI (~40 componentes em `src/components/ui/`) |
| Ícones | `lucide-react` |
| Animação | `framer-motion` 12 |
| Carrossel | `embla-carousel-react` 8 |
| Gráficos | `recharts` 2.15 (via `components/ui/chart.tsx`) |
| Formulários | `react-hook-form` + `zod` + `@hookform/resolvers` (uso pontual; a maioria dos forms admin usa `useState` controlado) |
| Estado servidor | `@tanstack/react-query` v5 — `QueryClientProvider` montado em `App.tsx`; **as telas admin não usam `useQuery`**, usam `useState` + `useEffect` + helpers `adminCrud` |
| Estado global | Nenhum (sem Redux/Zustand). Estado local por componente + sessão Supabase |
| Toasts | `sonner` (principal) + shadcn `toaster` (legado) |
| PDF | `jspdf` (laudo de vistoria) |
| Markdown | `react-markdown` (insights IA / manual) |
| Datas | `date-fns` 3.6 |
| Banco | PostgreSQL 15.6 (imagem `supabase/postgres:15.6.1.143`) |
| API REST | PostgREST v12.2.3 (schemas expostos: `public,storage,graphql_public`) |
| Auth | GoTrue v2.164.0 (email/senha, sem OAuth social configurado) |
| Storage | `supabase/storage-api:v1.11.13`, backend `file` em volume Docker |
| Gateway | Kong 2.8.1 (declarativo, `key-auth` por `apikey`, CORS) |
| Serverless | `supabase/edge-runtime:v1.62.2` (Deno) |
| Proxy/TLS | Nginx + Certbot (host), frontend servido por Nginx em container |
| Cliente HTTP | `@supabase/supabase-js` v2 no site público; `fetch()` cru para Edge Functions no admin |

## 1.3 Autenticação e integrações externas

- **Auth:** Supabase/GoTrue, e-mail+senha, `GOTRUE_MAILER_AUTOCONFIRM=false` (confirmação de e-mail via SMTP). Sem OAuth social. Sem cadastro público — usuários criados por admin.
- **Autorização:** tabela `public.user_roles` + função `public.has_role(uuid, app_role)` SECURITY DEFINER. Nenhuma role em tabela de perfil.
- **IA:** provedores em cascata — **DeepSeek** (`DEEPSEEK_API_KEY`, prioritário quando presente) → **Groq** (`GROQ_API_KEY`) → **Lovable AI Gateway** (`LOVABLE_API_KEY`, só Cloud).
- **Telegram:** notificação de visita agendada — modo direto (`TELEGRAM_BOT_TOKEN` + `TELEGRAM_CHAT_ID`) ou via connector Lovable (`LOVABLE_API_KEY` + `TELEGRAM_API_KEY`).
- **WhatsApp:** deep-link `wa.me/5585984326253` (sem API).
- Não há gateway de pagamento, nem webhooks de entrada.

## 1.4 Topologia de rede (self-hosted)

```text
Internet → Nginx (host, 443 TLS)
   ├── /            → simply-frontend:80        (SPA build Vite)
   └── /api/*       → simply-kong:8000
                        ├── /auth/v1/*      → simply-auth:9999     (GoTrue)
                        ├── /rest/v1/*      → simply-rest:3000     (PostgREST)
                        ├── /storage/v1/*   → simply-storage:5000  (Storage API)
                        └── /functions/v1/* → simply-functions:9000 (Deno)
                                              → simply-db:5432 (Postgres)
```

O frontend é buildado com `VITE_SUPABASE_URL=https://${SITE_DOMAIN}/api`. No navegador, `src/lib/adminCrud.ts` recalcula a base como `window.location.origin + "/api"` em qualquer host que não seja `*.lovable.app` / `*.lovableproject.com` — é isso que torna o app portável sem rebuild.

---

# 2. Esquema de Banco de Dados & Armazenamento

## 2.1 Enums (`public`)

| Enum | Valores |
|---|---|
| `app_role` | `admin`, `moderator`, `user` |
| `property_status` | `venda`, `aluguel` |
| `property_type` | `Apartamento`, `Casa`, `Cobertura`, `Terreno`, `Sala Comercial` |
| `contract_status` | `ativo`, `encerrado`, `cancelado`, `pendente` |
| `document_type` | `contrato`, `foto`, `documento`, `laudo`, `comprovante`, `outro` |
| `invoice_status` | `pendente`, `pago`, `atrasado`, `cancelado` |
| `lead_source` | `site`, `whatsapp`, `indicacao`, `portal`, `placa`, `telefone`, `chat`, `outro` |
| `lead_status` | `novo`, `contato_feito`, `visita_agendada`, `proposta`, `negociacao`, `fechado_ganho`, `fechado_perdido` |
| `transaction_type` | `receita`, `despesa` |
| `transaction_category` | `aluguel`, `venda`, `comissao`, `manutencao`, `condominio`, `iptu`, `seguro`, `taxa_administracao`, `reparo`, `outro` |

## 2.2 Tabelas

Convenções gerais: `id uuid PK DEFAULT gen_random_uuid()`, `created_at timestamptz NOT NULL DEFAULT now()`, `updated_at timestamptz NOT NULL DEFAULT now()` (quando existir, mantido por trigger), `user_id uuid NOT NULL` = autor/proprietário do registro (referência lógica a `auth.users`, **sem FK física**).

### `public.properties`
| Coluna | Tipo | Default / Constraint |
|---|---|---|
| id | uuid | PK, `gen_random_uuid()` |
| user_id | uuid | NOT NULL |
| title | text | NOT NULL |
| description | text | NULL |
| address | text | NOT NULL |
| neighborhood | text | NULL |
| city | text | NULL |
| price | numeric | NOT NULL |
| area | numeric | NOT NULL DEFAULT 0 |
| bedrooms | integer | NOT NULL DEFAULT 0 |
| suites | integer | NOT NULL DEFAULT 0 |
| bathrooms | integer | NOT NULL DEFAULT 0 |
| garage_spots | integer | NOT NULL DEFAULT 0 |
| pool_size | numeric | NULL |
| nearby_points | text | NULL |
| type | `property_type` | NOT NULL DEFAULT `'Casa'` |
| status | `property_status` | NOT NULL DEFAULT `'venda'` |
| featured | boolean | NOT NULL DEFAULT false |
| active | boolean | NOT NULL DEFAULT true |
| short_code | text | UNIQUE, gerado por trigger |
| created_at / updated_at | timestamptz | `now()` |

Relacionamentos 1:N → `property_media`, `leads`, `sales`, `rental_contracts`, `property_inspections`, `financial_transactions`.

### `public.property_media`
`id uuid PK`, `property_id uuid NOT NULL → properties(id) ON DELETE CASCADE`, `file_path text NOT NULL` (caminho no bucket `property-media`), `file_type text NOT NULL` (`image/*` ou `video/*`), `sort_order integer NOT NULL DEFAULT 0`, `created_at`.

### `public.property_code_sequences`
`prefix text PK` (`'A'` aluguel / `'V'` venda), `last_number integer NOT NULL DEFAULT 0`. Semeada com `('A',0), ('V',0)`.

### `public.contact_submissions`
`id`, `name text NOT NULL`, `email text NOT NULL`, `phone text`, `subject text`, `message text NOT NULL`, `source text` (ex.: `site`, `chat`), `chat_transcript text`, `visit_date timestamptz`, `read boolean NOT NULL DEFAULT false`, `created_at`.

### `public.scheduled_visits`
Agendamentos vindos do site/chat (nome, contato, imóvel, data). Inserção pública permitida; leitura só autenticado.

### `public.leads`
`id`, `user_id NOT NULL`, `name text NOT NULL`, `email`, `phone`, `source lead_source NOT NULL DEFAULT 'site'`, `status lead_status NOT NULL DEFAULT 'novo'`, `interest_type text`, `budget_min numeric`, `budget_max numeric`, `property_id uuid → properties(id)`, `assigned_to uuid`, `next_follow_up timestamptz`, `notes text`, `created_at`, `updated_at`.

### `public.lead_activities`
`id`, `lead_id uuid NOT NULL → leads(id) ON DELETE CASCADE`, `type text NOT NULL` (`nota`, `ligacao`, `whatsapp`, `email`, `visita`, `status`), `description text NOT NULL`, `user_id uuid`, `created_at`. Timeline/auditoria do lead.

### `public.sales`
`id`, `user_id NOT NULL`, `property_id uuid → properties(id)`, `lead_id uuid → leads(id)`, `buyer_name`, `buyer_email`, `buyer_phone`, `buyer_cpf`, `sale_value numeric`, `commission_rate numeric`, `commission_value numeric`, `probability numeric` (0–100, previsão de receita), `status text NOT NULL DEFAULT 'proposta'`, `proposal_date date`, `closing_date date`, `notes text`, `created_at`, `updated_at`.

### `public.sales_documents`
`id`, `sale_id uuid NOT NULL → sales(id)`, `user_id NOT NULL`, `document_type text NOT NULL DEFAULT 'documento'`, `file_name`, `file_path`, `file_type`, `notes`, `created_at`. Bucket `sales-documents` (privado).

### `public.tenants`
`id`, `user_id NOT NULL`, `name text NOT NULL`, `cpf_cnpj`, `rg`, `email`, `phone`, `address`, `notes`, `created_at`, `updated_at`.

### `public.tenant_documents`
`id`, `tenant_id uuid NOT NULL → tenants(id)`, `user_id`, `document_type`, `file_name`, `file_path`, `file_type`, `notes`, `created_at`. Bucket `tenant-documents` (privado).

### `public.rental_contracts`
`id`, `user_id NOT NULL`, `property_id uuid → properties(id)`, `tenant_id uuid → tenants(id)`, `monthly_rent numeric NOT NULL`, `deposit_amount numeric`, `start_date date NOT NULL`, `end_date date NOT NULL`, `payment_day integer NOT NULL DEFAULT 5`, `adjustment_index text` (IGPM/IPCA), `late_fee_percentage numeric`, `commission_rate numeric`, `commission_value numeric`, `status contract_status NOT NULL DEFAULT 'ativo'`, `notes`, `created_at`, `updated_at`.

### `public.contract_documents`
`id`, `contract_id uuid → rental_contracts(id)`, `user_id NOT NULL`, `document_type document_type NOT NULL DEFAULT 'documento'`, `file_name`, `file_path`, `file_type`, `notes`, `created_at`. Bucket `contract-documents` (privado).

### `public.property_inspections`
`id`, `user_id NOT NULL`, `property_id uuid NOT NULL → properties(id)`, `tenant_id uuid → tenants(id)`, `contract_id uuid → rental_contracts(id)`, `inspection_type text NOT NULL DEFAULT 'entrada'` (entrada/saída/periódica), `inspection_date date NOT NULL DEFAULT now()`, `inspector_name`, `status text NOT NULL DEFAULT 'rascunho'`, `keys_delivered integer`, `meter_reading_water/_electricity/_gas text`, `painting_condition`, `floor_condition`, `electrical_condition`, `plumbing_condition`, `rooms_condition`, `general_notes`, `created_at`, `updated_at`.

### `public.inspection_media`
`id`, `inspection_id uuid NOT NULL → property_inspections(id)`, `user_id NOT NULL`, `media_category text NOT NULL DEFAULT 'geral'`, `file_name`, `file_path`, `file_type`, `notes`, `created_at`. Bucket `inspection-media` (privado).

### `public.financial_transactions`
`id`, `user_id NOT NULL`, `type transaction_type NOT NULL`, `category transaction_category NOT NULL DEFAULT 'outro'`, `amount numeric NOT NULL`, `description text NOT NULL`, `date date NOT NULL DEFAULT now()`, `due_date date`, `paid_date date`, `status invoice_status NOT NULL DEFAULT 'pendente'`, `payment_method text`, `receipt_path text`, `property_id → properties(id)`, `tenant_id → tenants(id)`, `contract_id → rental_contracts(id)`, `created_at`.

### `public.user_roles`
`id uuid PK`, `user_id uuid NOT NULL`, `role app_role NOT NULL`, `UNIQUE (user_id, role)`.

> Não existem **views** no schema `public`.

## 2.3 Funções SQL

| Função | Tipo | Comportamento |
|---|---|---|
| `public.has_role(_user_id uuid, _role app_role) → boolean` | `sql`, `STABLE`, `SECURITY DEFINER`, `SET search_path = public` | `EXISTS (SELECT 1 FROM user_roles WHERE user_id=_user_id AND role=_role)`. Base de todas as RLS admin; evita recursão. |
| `public.update_updated_at_column() → trigger` | `plpgsql`, `SET search_path = public` | `NEW.updated_at = now()`. |
| `public.generate_property_short_code() → trigger` | `plpgsql`, `SECURITY DEFINER` | BEFORE INSERT em `properties`: prefixo `A` se `status='aluguel'`, senão `V`; incrementa `property_code_sequences.last_number` do prefixo com `RETURNING`; grava `short_code = prefix || '-' || lpad(n::text,4,'0')` (ex.: `V-0007`). |
| `public.update_property_short_code_on_status_change() → trigger` | `plpgsql`, `SECURITY DEFINER` | BEFORE UPDATE: se `OLD.status IS DISTINCT FROM NEW.status`, **regera** o `short_code` com o novo prefixo e novo número da sequência correspondente. |

Não há RPCs chamados pelo frontend (`Functions: {}` em `types.ts`).

## 2.4 Triggers

| Trigger | Tabela | Evento | Função |
|---|---|---|---|
| `set_property_short_code` / `set_short_code` | `properties` | BEFORE INSERT | `generate_property_short_code()` |
| `update_property_short_code_on_status` / `update_short_code` | `properties` | BEFORE UPDATE | `update_property_short_code_on_status_change()` |
| `update_properties_updated_at` | `properties` | BEFORE UPDATE | `update_updated_at_column()` |
| `update_leads_updated_at` | `leads` | BEFORE UPDATE | idem |
| `update_sales_updated_at` | `sales` | BEFORE UPDATE | idem |
| `update_tenants_updated_at` | `tenants` | BEFORE UPDATE | idem |
| `update_rental_contracts_updated_at` | `rental_contracts` | BEFORE UPDATE | idem |
| `update_inspections_updated_at` | `property_inspections` | BEFORE UPDATE | idem |

> Na recriação, usar `DROP TRIGGER IF EXISTS` antes de cada `CREATE TRIGGER` (os nomes duplicados acima são resultado de renomeações históricas; manter apenas um par por evento).

## 2.5 RLS — regras por tabela

Todas as tabelas de `public` têm `ENABLE ROW LEVEL SECURITY`. Padrão de acesso:

| Tabela | Público (`anon`) | `authenticated` |
|---|---|---|
| `properties` | SELECT quando `active = true` | admin (`has_role(auth.uid(),'admin')`) faz tudo; dono (`user_id = auth.uid()`) faz CRUD do próprio e vê inativos |
| `property_media` | SELECT livre | admin gerencia; dono insere/atualiza/deleta mídia de imóvel próprio |
| `contact_submissions` | INSERT livre (`Anyone can submit contact`) | admin/autenticado vê, atualiza (`read`) e deleta |
| `scheduled_visits` | INSERT livre | autenticado vê; admin atualiza/deleta |
| `leads`, `lead_activities`, `sales`, `sales_documents`, `tenants`, `tenant_documents`, `rental_contracts`, `contract_documents`, `property_inspections`, `inspection_media`, `financial_transactions`, `property_code_sequences` | sem acesso | `FOR ALL USING (has_role(auth.uid(),'admin')) WITH CHECK (has_role(auth.uid(),'admin'))` |
| `user_roles` | sem acesso | SELECT: própria role (`user_id = auth.uid()`) ou admin; INSERT/UPDATE/DELETE: somente admin |

**GRANTs obrigatórios** (PostgREST não concede por padrão):

```sql
GRANT SELECT ON public.properties, public.property_media TO anon;
GRANT INSERT ON public.contact_submissions, public.scheduled_visits TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO service_role;
```

> **Armadilha self-hosted documentada:** conceder grants antes de criar o schema gera `permission denied`; o pipeline correto está em `docker/volumes/db/init/00-passwords.sh` + `docker/sync-db-passwords.sh` + `docker/bootstrap-db.sh`.
> **Armadilha RLS:** `auth.uid()/role()/email()` precisam ler tanto `request.jwt.claim.*` quanto `request.jwt.claims` (PostgREST com `PGRST_DB_USE_LEGACY_GUCS`).

## 2.6 Storage (buckets)

| Bucket | Público | Conteúdo | Tabela espelho |
|---|---|---|---|
| `property-media` | **sim** | fotos e vídeos dos imóveis | `property_media` |
| `sales-documents` | não | documentos de venda | `sales_documents` |
| `tenant-documents` | não | documentos do inquilino | `tenant_documents` |
| `contract-documents` | não | contratos e anexos | `contract_documents` |
| `inspection-media` | não | fotos de vistoria | `inspection_media` |

Políticas em `storage.objects`: leitura pública apenas em `property-media`; nos demais, leitura/upload/update/delete restritos a `authenticated` (e admin nas variantes `sales-documents`). Limite de arquivo: `FILE_SIZE_LIMIT=52428800` (50 MB).

Regras específicas de self-hosted (obrigatórias):
- O role `supabase_storage_admin` precisa de `BYPASSRLS`.
- `FormData`/multipart falha no edge-runtime Deno self-hosted → uploads são feitos com **corpo binário puro** e metadados em query/headers (`adminStorageUpload`).
- URLs públicas servidas via Kong precisam de `?apikey=<ANON_KEY>` para funcionar em `<img>` (implementado em `src/lib/mediaUrl.ts`).

---

# 3. Mapeamento Arquivo por Arquivo

## 3.1 Raiz e configuração

| Arquivo | Responsabilidade | Dependências / Efeitos |
|---|---|---|
| `index.html` | Shell da SPA; SEO (title/description/keywords com "CRECI 29379"), OG/Twitter, favicon `/favicon.png`, `#root` | — |
| `vite.config.ts` | Build/dev server (host `::`, porta `8080`), alias `@ → ./src`, `lovable-tagger` só em dev | — |
| `tailwind.config.ts` | Tokens HSL semânticos, fontes display/body, animações, plugins animate/typography | — |
| `postcss.config.js` | Tailwind + Autoprefixer | — |
| `components.json` | Configuração shadcn/ui (aliases, estilo) | — |
| `tsconfig*.json` | TS 5.8, paths `@/*` | — |
| `eslint.config.js` | ESLint 9 flat config + react-hooks + react-refresh | — |
| `vitest.config.ts`, `src/test/setup.ts`, `src/test/example.test.ts` | Testes unitários (jsdom + testing-library) | — |
| `playwright.config.ts`, `playwright-fixture.ts` | E2E opcional | — |
| `public/robots.txt`, `public/sitemap.xml`, `public/favicon.png` | SEO/estáticos | — |
| `.env` | `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`, `VITE_SUPABASE_PROJECT_ID` | consumido em build |

## 3.2 Bootstrap da aplicação

| Arquivo | Responsabilidade | Entradas / Efeitos |
|---|---|---|
| `src/main.tsx` | `createRoot` + `<App />` + import de `index.css` | — |
| `src/App.tsx` | Providers (`QueryClientProvider`, `TooltipProvider`, `Toaster`, `Sonner`) e `BrowserRouter` com todas as rotas | Nenhuma mutação |
| `src/index.css` | Design system: variáveis HSL, gradientes, sombras, utilitários (`gradient-primary`, etc.) | — |
| `src/App.css` | Resíduo do template | — |
| `src/vite-env.d.ts` | Tipos de `import.meta.env` | — |

## 3.3 Integração com o backend

| Arquivo | Responsabilidade | Entradas | Efeitos colaterais |
|---|---|---|---|
| `src/integrations/supabase/client.ts` | Instancia `createClient<Database>` com `VITE_SUPABASE_URL` / `VITE_SUPABASE_PUBLISHABLE_KEY`; `persistSession`, `autoRefreshToken` | env | Grava sessão no storage do browser |
| `src/integrations/supabase/previewAuthStorage.ts` | Adaptador de storage de sessão (específico do preview Lovable) | — | Leitura/escrita de sessão |
| `src/integrations/supabase/types.ts` | Tipos gerados do schema (`Database`, `Tables`, `Enums`, `Constants`) | — | — |
| `src/lib/adminCrud.ts` | **Camada de dados do admin.** Resolve a base URL (`window.location.origin + /api` fora do Lovable), anexa `Authorization: Bearer <access_token>` + `apikey`, e expõe `adminSelect/adminInsert/adminUpdate/adminDelete/adminStorageUpload/adminStorageDelete/adminStorageSignedUrl/adminAiGenerate`. Padroniza erros (`message/code/stage/debugId/status`) | tabela, filtros `match`, `order`, `select`, payloads | POST em `/functions/v1/admin-crud` (service_role, bypassa RLS); upload binário; fallback para `/functions/v1/ai-generate` |
| `src/lib/mediaUrl.ts` | Converte `file_path` em URL pública do bucket `property-media`, anexando `?apikey=` quando via Kong | `file_path` | — |
| `src/lib/utils.ts` | `cn()` (clsx + tailwind-merge) | — | — |

### Submódulo de salvamento de imóvel

| Arquivo | Responsabilidade | Efeitos |
|---|---|---|
| `src/lib/propertyForm/types.ts` | Tipos do formulário (`PropertyFormState`, arquivos pendentes, mídias existentes) | — |
| `src/lib/propertyForm/normalizers.ts` | Normaliza número/texto (preço, área, quartos) antes de enviar | — |
| `src/lib/propertyForm/propertyPayload.ts` | Monta o payload exato de `properties` a partir do estado | — |
| `src/lib/propertyForm/media.ts` | Remove mídias marcadas (`adminDelete("property_media")` + delete no bucket) | DELETE em `property_media` e storage |
| `src/lib/propertyForm/errors.ts` | Normaliza mensagens de erro | — |
| `src/lib/propertyForm/savePropertyWithMedia.ts` | **Transação lógica:** insere/atualiza `properties` → faz upload de cada arquivo em `property-media` → insere linhas em `property_media` com `sort_order`. Em falha, executa **rollback** (apaga mídias criadas e, se era criação, apaga o imóvel) | INSERT/UPDATE/DELETE em `properties` e `property_media`; upload/delete no storage |
| `src/lib/propertyFormService.ts` | Re-export de compatibilidade | — |

## 3.4 Páginas (`src/pages/`)

| Arquivo | Responsabilidade | Dados | Efeitos |
|---|---|---|---|
| `Index.tsx` | Home: compõe Navbar, Hero, Highlights, Featured, Opportunities, Trust, About, Testimonials, Contact, Footer, ChatWidget, WhatsAppButton | — | — |
| `Properties.tsx` | Listagem `/imoveis`: filtros por status (venda/aluguel), tipo, cidade/bairro, faixa de preço e quartos; grid responsivo | `supabase.from("properties").eq("active",true)` + `property_media` | Somente leitura |
| `PropertyDetail.tsx` | Detalhe `/imoveis/:id`: galeria Embla (loop, swipe, contador, thumbs, aspect ratio responsivo), lightbox slideshow em tela cheia com `object-contain` e limites de viewport, dados do imóvel, CTA WhatsApp `(85) 98432-6253` | `properties` + `property_media` por `id` | Somente leitura |
| `Services.tsx` | Página institucional de serviços | estático | — |
| `Manual.tsx` | Manual público/interativo do sistema | estático | — |
| `Admin.tsx` | Shell do ERP: escuta `onAuthStateChange` + `getSession`; valida role via `adminSelect("user_roles", { match:{user_id, role:'admin'} })`; renderiza `AdminLogin` se sem sessão, tela "Acesso negado" se sem role; carrega `properties` + `property_media`; controla a aba ativa e o formulário | sessão, `user_roles`, `properties`, `property_media` | `supabase.auth.signOut()` no logout |
| `NotFound.tsx` | 404 | — | — |

## 3.5 Componentes públicos (`src/components/`)

| Arquivo | Responsabilidade | Dados / Efeitos |
|---|---|---|
| `Navbar.tsx` | Navegação fixa, menu mobile, alvos de toque ampliados | — |
| `NavLink.tsx` | Link com estado ativo | props `to`, `children` |
| `HeroSection.tsx` | Hero com imagens e CTA de busca | — |
| `HighlightsSection.tsx` | Carrossel responsivo de destaques | lê `properties` (`featured=true`) + `property_media` |
| `FeaturedProperties.tsx` | Grid de imóveis em destaque | lê `properties` + `property_media` |
| `OpportunitiesSection.tsx` | Oportunidades/promoções | lê `properties` + `property_media` |
| `TrustSection.tsx` | Selos de confiança; **card único com "CRECI 29379"** | estático |
| `AboutSection.tsx` | Sobre a corretora | estático |
| `TestimonialsSection.tsx` | Depoimentos | estático |
| `ContactSection.tsx` | Formulário de contato + telefone com ícone WhatsApp | INSERT em `contact_submissions` |
| `ChatWidget.tsx` | Chat IA flutuante: conversa, qualificação e agendamento | POST `/functions/v1/chat`; INSERT em `contact_submissions`, `scheduled_visits`; lê `properties` |
| `WhatsAppButton.tsx` | Botão flutuante `wa.me/5585984326253` | — |
| `Footer.tsx` | Rodapé institucional/contatos | — |
| `src/components/ui/*` | shadcn/ui (accordion…tooltip, `carousel.tsx`, `chart.tsx`, `sidebar.tsx`, `sonner.tsx`) | Sem efeitos de dados |

## 3.6 Componentes do admin (`src/components/admin/`)

| Arquivo | Responsabilidade | Tabelas acessadas (via `adminCrud`) | Efeitos colaterais |
|---|---|---|---|
| `AdminLogin.tsx` | Login e-mail/senha | — | `supabase.auth.signInWithPassword` |
| `AdminSidebar.tsx` | Navegação das 15 abas; drawer responsivo no mobile | — | Troca de aba, logout |
| `DashboardTab.tsx` | KPIs: receita, despesa, lucro, previsão 30 dias (`Σ sale_value × probability/100` de vendas abertas), gráfico mensal, alertas, registros recentes | `financial_transactions`, `sales`, `leads`, `properties`, `rental_contracts`, `tenants`, `property_inspections` | Leitura |
| `PropertyList.tsx` | Lista/edita/remove imóveis; toggle `active`/`featured`; abre Marketing Kit | `properties` (update/delete) | Delete cascata de mídias |
| `PropertyForm.tsx` | Cadastro/edição com upload múltiplo, reordenação e preview | via `savePropertyWithMedia` | Insert/Update + upload/rollback |
| `MarketingKit.tsx` | Kit de marketing: flyer imprimível, legenda Instagram, mensagem WhatsApp e pitch de vendas, gerados por IA, com abas e botões de cópia | `adminAiGenerate` | POST `admin-crud` (`ai-generate`) com fallback `/functions/v1/ai-generate` |
| `ContactsTab.tsx` | Caixa de entrada de contatos; marcar lido; excluir | `contact_submissions` | Update/Delete |
| `LeadsTab.tsx` | Funil: visão lista e **Kanban** por `lead_status`, timeline de atividades, registro manual de atividade, matchmaking automático de imóveis por faixa de orçamento/tipo | `leads`, `lead_activities`, `properties` | Insert/Update/Delete |
| `SalesTab.tsx` | CRUD de vendas; **select de imóvel** (código, título, bairro/cidade, preço) que autopreenche `sale_value`; comissão e probabilidade | `sales`, `properties` | Insert/Update/Delete |
| `SaleDocuments.tsx` | Anexos da venda (upload/lista/exclusão) | `sales_documents` | Upload/delete em `sales-documents` |
| `TenantsTab.tsx` | CRUD de inquilinos + documentos; **antes de excluir**, limpa dependências (documentos, contratos, vistorias, transações) para não bater em FK | `tenants`, `tenant_documents`, `rental_contracts`, `property_inspections`, `financial_transactions` | Deletes encadeados |
| `RentalsTab.tsx` | CRUD de contratos de aluguel + documentos; mesma limpeza de dependências no delete | `rental_contracts`, `contract_documents`, `properties`, `tenants`, `financial_transactions`, `property_inspections` | Deletes encadeados |
| `InspectionsTab.tsx` | Vistorias: campos de estado do imóvel, leituras de medidores, chaves, mídias por categoria | `property_inspections`, `inspection_media`, `properties`, `tenants`, `rental_contracts` | Upload em `inspection-media`; gera PDF |
| `generateInspectionPdf.ts` | Monta o laudo de vistoria em PDF (jsPDF) com cabeçalho, campos e fotos | recebe vistoria + mídias | Download de arquivo |
| `FinancialTab.tsx` | Receitas/despesas, status de pagamento, vínculos com imóvel/inquilino/contrato, totais | `financial_transactions` | Insert/Update/Delete |
| `ReportsTab.tsx` | Relatórios consolidados e exportações | todas as tabelas de negócio | Leitura + export |
| `InsightsTab.tsx` | Insights de IA sobre a carteira (markdown) | POST `/functions/v1/ai-insights` | Chamada IA |
| `BackupTab.tsx` | Backup/restore v2.0 em JSON: exporta todas as tabelas; na restauração respeita a ordem filho-antes-de-pai, inclui `property_code_sequences` e `user_roles`, com fallback de inserção linha a linha | todas | Deletes/Inserts massivos |
| `UsersTab.tsx` | Gestão de usuários e roles | `user_roles` via função | POST `/functions/v1/create-admin-user` |
| `PasswordTab.tsx` | Troca de senha do usuário logado | — | `supabase.auth.updateUser` |
| `ManualTab.tsx` | Manual interativo dentro do admin | estático | — |

## 3.7 Hooks

| Arquivo | Responsabilidade |
|---|---|
| `src/hooks/use-mobile.tsx` | `useIsMobile()` via `matchMedia` (breakpoint 768px) |
| `src/hooks/use-toast.ts` | Reducer de toasts do shadcn |

## 3.8 Edge Functions (`supabase/functions/`)

| Função | JWT | Responsabilidade | Entradas | Efeitos |
|---|---|---|---|---|
| `admin-crud/index.ts` (585 l.) | verificado no código | **Roteador central do admin.** Valida `Authorization` → resolve usuário → exige role `admin` → executa com `service_role` (bypassa RLS). Ações: `select`, `insert`, `update`, `delete`, `storage-delete`, `storage-signed-url`, upload binário via query (`?storage_action=upload&bucket&path&upsert`) e `ai-generate` (legado). Versão no header `x-admin-crud-version`; `x-admin-crud-request-id` para rastreio | JSON `{action, table, data, match, select, order}` ou corpo binário | Escreve em qualquer tabela/bucket |
| `ai-generate/index.ts` (151 l.) | `verify_jwt = false` (valida internamente) | Geração de conteúdo IA dedicada (Marketing Kit). Resolve provedor DeepSeek → Groq → Lovable; valida admin; retorna `{data: texto}` | `{prompt, systemPrompt, temperature, model}` | Chamada HTTP ao provedor |
| `ai-insights/index.ts` (220 l.) | `verify_jwt = false` | Coleta métricas da carteira e devolve análise em markdown | `{}` | Leitura via service_role + chamada IA |
| `chat/index.ts` (211 l.) | `verify_jwt = false` | Chat público do site: prioridade Groq → Lovable; contexto de imóveis; suporta `propertyId` | `{messages, propertyId}` | Leitura de `properties`; chamada IA |
| `create-admin-user/index.ts` (139 l.) | `verify_jwt = false` | Cria usuário via Admin API do GoTrue e insere `user_roles` | `{email, password, role}` | Cria em `auth.users` e `user_roles` |
| `admin-storage/index.ts` (163 l.) | — | Operações de storage isoladas para self-hosted (upload binário/delete/URL assinada) | headers de metadados | Escreve nos buckets |
| `notify-telegram/index.ts` (86 l.) | `verify_jwt = false` | Notificação de visita agendada; dual-mode: bot direto (`TELEGRAM_BOT_TOKEN`) ou connector Lovable | `{message}` | HTTP para API do Telegram |
| `supabase/config.toml` | — | `verify_jwt = false` para `chat`, `notify-telegram`, `create-admin-user`, `ai-insights`, `ai-generate` | — | — |

## 3.9 Infraestrutura (`docker/`)

| Arquivo | Responsabilidade |
|---|---|
| `docker-compose.yml` | Serviços `db`, `auth`, `rest`, `storage`, `kong`, `functions`, `frontend`; rede `simply-net`; volumes `simply_pgdata`, `simply_storage` |
| `Dockerfile` | Build multi-stage do frontend (Node 20 → Nginx), recebe `VITE_*` como build args |
| `nginx-frontend.conf` / `nginx-site.conf` | Fallback SPA no container; reverse proxy + TLS no host |
| `volumes/kong/kong.yml(.template)` | Rotas `/auth/v1`, `/rest/v1`, `/storage/v1`, `/functions/v1` com `key-auth` e CORS |
| `volumes/db/init/00-passwords.sh` | Cria roles, senhas e grants iniciais |
| `volumes/db/init/01-schema.sql` | Init mínimo (schema real vem do bootstrap) |
| `install.sh` (v16) | Instalador CLI com 14 estágios: checagens de SO, Docker/Nginx/Certbot, geração de credenciais/JWT, Kong, functions, bootstrap do banco, criação do admin, retries |
| `bootstrap-db.sh` | Pipeline determinístico: credenciais → schema core (`sql/selfhosted-admin-recovery.sql`) → storage (`sql/bootstrap-storage.sql`) + validação de grants |
| `sync-db-passwords.sh` | Sincroniza senhas dos roles e grants |
| `render-kong-config.sh`, `render-functions-main.sh`, `sync-functions.sh` | Geram `kong.yml` e o roteador `main/index.ts` do edge-runtime |
| `create-admin.sh`, `fix-auth-keys.sh`, `fix-vps-admin.sh` | Criação/recuperação de admin; regeneração de chaves derivadas do JWT |
| `ensure-storage-buckets.sh` | Garante buckets e políticas |
| `backup.sh` / `restore.sh` / `full-wipe.sh` / `reset-db.sh` | Backup com retenção de 10, restore com backup de segurança e wipe do schema |
| `update.sh`, `quick-update.sh`, `update-from-github.sh`, `redeploy.sh` | Atualização e recriação forçada de `functions`/`kong`/`frontend` |
| `health-check.sh`, `status.sh`, `logs.sh`, `validate.sh`, `validate-install.sh`, `debug-*.sh` | Diagnóstico |
| `setup-ssl.sh` | Certbot |
| `DEPLOY-CHECKLIST.md`, `README.md`, `.env.example`, `.env.functions.example` | Documentação e modelos de configuração |

---

# 4. Rotas, Fluxos de Usuário & Autenticação

## 4.1 Rotas do frontend (`src/App.tsx`)

| Rota | Componente | Proteção |
|---|---|---|
| `/` | `Index` | pública |
| `/imoveis` | `Properties` | pública |
| `/imoveis/:id` | `PropertyDetail` | pública |
| `/servicos` | `Services` | pública |
| `/manual` | `Manual` | pública |
| `/admin` | `Admin` | **protegida** (sessão + role `admin`) |
| `*` | `NotFound` | pública |

O ERP não usa sub-rotas: as 15 áreas são abas controladas pelo estado `activeTab` — `dashboard`, `properties`, `contacts`, `password`, `users`, `leads`, `sales`, `tenants`, `rentals`, `inspections`, `financial`, `reports`, `backup`, `insights`, `manual`.

## 4.2 Guard de rota

Implementado dentro de `Admin.tsx` (não há `<ProtectedRoute>`):

1. `supabase.auth.onAuthStateChange` é registrado **antes** de `getSession()` (evita perda de evento).
2. `authLoading` → spinner.
3. Sem sessão → renderiza `<AdminLogin />` (sem redirect de URL).
4. Com sessão → `adminSelect("user_roles", { match: { user_id, role: "admin" } })`. Lista vazia ⇒ tela "Acesso negado" com botão Sair; erro ⇒ toast e acesso negado.
5. Só com `isAdmin === true` o shell do ERP é montado.

Defesa em profundidade: RLS no banco + verificação de role dentro de `admin-crud` antes de qualquer operação com `service_role`.

## 4.3 Endpoints de backend

| Método/Rota | Auth | Uso |
|---|---|---|
| `POST /api/functions/v1/admin-crud` | Bearer + apikey + role admin | Todo CRUD e storage do ERP |
| `POST /api/functions/v1/ai-generate` | Bearer + apikey | Marketing Kit |
| `POST /api/functions/v1/ai-insights` | Bearer + apikey | Insights |
| `POST /api/functions/v1/chat` | apikey (público) | Chat do site |
| `POST /api/functions/v1/create-admin-user` | Bearer admin | Criação de usuários |
| `POST /api/functions/v1/notify-telegram` | apikey | Notificação de visita |
| `GET/POST /api/rest/v1/*` | apikey (+ Bearer) | Leituras públicas do site |
| `/api/auth/v1/*` | apikey | GoTrue |
| `/api/storage/v1/object/public/property-media/*?apikey=` | apikey | Imagens públicas |

## 4.4 Fluxo de autenticação

1. **Cadastro:** não existe self-signup. Admin cria usuários em `UsersTab` → `create-admin-user` usa a Admin API do GoTrue (nunca SQL direto, para manter o GoTrue sincronizado) e insere a role em `user_roles`.
2. **Confirmação de e-mail:** `GOTRUE_MAILER_AUTOCONFIRM=false`; SMTP configurado por env; caminhos `/auth/v1/verify`.
3. **Login:** `signInWithPassword` → JWT HS256 assinado com `JWT_SECRET` (exp 3600s) → persistido no storage do browser.
4. **Refresh:** automático (`autoRefreshToken: true`).
5. **Reset de senha:** e-mail de recovery pelo GoTrue; troca dentro do app em `PasswordTab` (`auth.updateUser`).
6. **Logout:** `supabase.auth.signOut()` → `navigate("/")`.
7. **Recuperação operacional (VPS):** `bash docker/create-admin.sh <email> <senha>`; em caso de `401`, `bash docker/fix-auth-keys.sh` (regenera ANON/SERVICE_ROLE a partir do `JWT_SECRET`, atualiza `.env` + Kong, reinicia containers e sincroniza senhas do banco).
8. **Login social:** não implementado.

---

# 5. Variáveis de Ambiente & Configurações

## 5.1 Frontend (`.env` na raiz — build-time, Vite)

| Variável | Uso |
|---|---|
| `VITE_SUPABASE_URL` | Base da API. Self-hosted: `https://<dominio>/api` |
| `VITE_SUPABASE_PUBLISHABLE_KEY` | Chave anônima (JWT `role: anon`), enviada como `apikey` |
| `VITE_SUPABASE_PROJECT_ID` | Identificação, opcional em self-hosted |

## 5.2 Infraestrutura (`docker/.env`)

| Variável | Uso |
|---|---|
| `SITE_DOMAIN` | Domínio público; define `API_EXTERNAL_URL` e `GOTRUE_SITE_URL` |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | Credenciais do Postgres (padrão `supabase_admin` / `simply_db`) |
| `JWT_SECRET` | Segredo HS256 (≥32 chars) compartilhado por GoTrue, PostgREST, Storage e Functions |
| `ANON_KEY` | JWT `role: anon` derivado do `JWT_SECRET` |
| `SERVICE_ROLE_KEY` | JWT `role: service_role` — usado pelas Edge Functions |
| `SMTP_HOST` / `SMTP_PORT` / `SMTP_USER` / `SMTP_PASS` / `SMTP_SENDER_NAME` / `SMTP_ADMIN_EMAIL` | Envio de e-mails de confirmação e recuperação |
| `GROQ_API_KEY` | IA (chat, insights, marketing) |
| `DEEPSEEK_API_KEY` | IA prioritária do Marketing Kit (opcional) |
| `LOVABLE_API_KEY` | Gateway Lovable (opcional, só Cloud) |
| `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` | Notificações via bot direto |
| `TELEGRAM_API_KEY` | Notificações via connector Lovable (alternativa) |
| `KONG_HTTP_PORT` | Porta local do gateway (padrão 8000, bind 127.0.0.1) |
| `FRONTEND_PORT` | Porta local do frontend (padrão 3000, bind 127.0.0.1) |

**Regra crítica:** `ANON_KEY` e `SERVICE_ROLE_KEY` devem ser sempre derivados do `JWT_SECRET` vigente. Divergência produz `401 Unauthorized` em toda a stack.

## 5.3 `.env.example` recomendado (raiz)

```bash
VITE_SUPABASE_URL="https://seudominio.com.br/api"
VITE_SUPABASE_PUBLISHABLE_KEY="<ANON_KEY>"
VITE_SUPABASE_PROJECT_ID="simply"
```

---

# 6. Roteiro Passo a Passo de Portabilidade para Claude Code

## Etapa 1 — Ambiente e repositório
1. Requisitos: Node 20+, npm ou bun, Docker + Docker Compose, `psql`, `openssl`.
2. `git clone <repo> simply-imoveis && cd simply-imoveis && npm install`.
3. Criar `.env` na raiz conforme 5.3.
4. Validar toolchain: `npx tsc --noEmit && npm run build`.

## Etapa 2 — Provisionamento e migração do banco
1. `cp docker/.env.example docker/.env` e preencher domínio, SMTP e chaves de IA.
2. Gerar segredos: `openssl rand -hex 32` para `JWT_SECRET` e `POSTGRES_PASSWORD`; derivar `ANON_KEY` e `SERVICE_ROLE_KEY` do `JWT_SECRET` (HS256, claims `{"role":"anon"|"service_role","iss":"supabase","iat":...,"exp":...}`).
3. `cd docker && docker compose up -d db` e aguardar o healthcheck.
4. Aplicar o DDL na ordem: **extensões (`pgcrypto`) → enums (2.1) → tabelas (2.2) → GRANTs (2.5) → `ENABLE ROW LEVEL SECURITY` → funções (2.3) → triggers (2.4) → policies (2.5) → buckets e policies de storage (2.6) → seed `property_code_sequences('A',0),('V',0)`**.
   - Reaproveitar os 21 arquivos de `supabase/migrations/` em ordem cronológica **byte a byte**, ou rodar `bash docker/bootstrap-db.sh`.
5. Conferir grants: nenhum `permission denied` em `storage.objects`/`storage.buckets` para `authenticated`/`service_role`; `supabase_storage_admin` com `BYPASSRLS`.

## Etapa 3 — Clientes e serviços
1. `bash docker/render-kong-config.sh` (injeta as chaves em `kong.yml`).
2. `bash docker/render-functions-main.sh` e `bash docker/sync-functions.sh` — o roteador `volumes/functions/main/index.ts` **precisa listar as 7 funções**: `admin-crud`, `admin-storage`, `ai-generate`, `ai-insights`, `chat`, `create-admin-user`, `notify-telegram`. Função ausente no roteador é a causa clássica de "Function not found" / "Ação inválida".
3. `docker compose up -d` e depois `bash docker/health-check.sh`.
4. Criar o admin: `bash docker/create-admin.sh <email> <senha>`.

## Etapa 4 — Tipos TypeScript
1. Regenerar `src/integrations/supabase/types.ts` a partir do schema (ou copiar o arquivo atual — é a fonte canônica dos tipos).
2. Manter `Constants.public.Enums` alinhado com os enums do banco; as telas montam os selects a partir deles.

## Etapa 5 — Camada de dados
1. Portar `src/integrations/supabase/client.ts` e `src/lib/adminCrud.ts` **sem alterar** a resolução de base URL e o envio de `Authorization` + `apikey`.
2. Portar `src/lib/mediaUrl.ts` preservando o `?apikey=` (sem ele, imagens públicas quebram atrás do Kong).
3. Portar `src/lib/propertyForm/*` mantendo o rollback transacional.
4. Publicar as Edge Functions preservando a ordem de validação em `admin-crud`: CORS → token → usuário → role admin → ação; `table` é obrigatório **somente** para ações CRUD.

## Etapa 6 — Interface
1. Base: `src/index.css`, `tailwind.config.ts`, `src/components/ui/*` (shadcn). Nunca usar cores hardcoded — só tokens semânticos.
2. Componentes públicos → páginas públicas (`Index`, `Properties`, `PropertyDetail`, `Services`, `Manual`).
3. Shell do admin (`Admin.tsx` + `AdminSidebar`) → abas, na ordem de dependência: `PropertyForm/PropertyList` → `LeadsTab` → `SalesTab`/`SaleDocuments` → `TenantsTab` → `RentalsTab` → `InspectionsTab` → `FinancialTab` → `DashboardTab`/`ReportsTab` → `BackupTab`/`UsersTab`/`InsightsTab`/`ManualTab`.
4. Mobile-first obrigatório em todas as telas.

## Etapa 7 — Validação e conformidade

- [ ] `npm run build` e `npx tsc --noEmit` sem erros; `npm run test` verde.
- [ ] `/` e `/imoveis` carregam imóveis e imagens sem autenticação.
- [ ] `/imoveis/:id`: carrossel com swipe, lightbox ajustando a imagem ao viewport.
- [ ] Formulário de contato grava em `contact_submissions`; chat responde e agenda visita; Telegram notifica.
- [ ] Login em `/admin`; usuário sem role recebe "Acesso negado".
- [ ] Criar imóvel com 5 fotos; falha simulada no upload deve reverter tudo (rollback).
- [ ] `short_code` gerado no formato `V-0001`; ao trocar `status` para aluguel, vira `A-000N`.
- [ ] Excluir inquilino e contrato com dependências não gera erro de FK.
- [ ] Marketing Kit gera os 4 formatos; Insights retorna markdown.
- [ ] Backup exporta e restaura sem violar ordem de FKs.
- [ ] `bash docker/validate-install.sh` e `bash docker/health-check.sh` totalmente verdes.
- [ ] `docker/backup.sh` agendado em cron, com retenção de 10 execuções.

---

## Anexo — Regras de negócio que não podem ser perdidas

1. **Código do imóvel:** prefixo `A` (aluguel) / `V` (venda) + número sequencial de 4 dígitos; sequência independente por prefixo; regerado ao mudar o status.
2. **Comissão:** `commission_value = valor × commission_rate / 100` em vendas e contratos.
3. **Previsão de receita (Dashboard):** `Σ (sale_value × probability / 100)` para vendas ainda não fechadas, janela de 30 dias.
4. **Lucro:** `Σ receitas pagas − Σ despesas pagas` sobre `financial_transactions`.
5. **Matchmaking de leads:** imóveis ativos cujo `price` cai entre `budget_min` e `budget_max` e cujo tipo/status casa com o `interest_type` do lead.
6. **Exclusões:** sempre limpar filhos antes do pai (documentos → vistorias → transações → contratos → inquilino/imóvel).
7. **Identidade:** marca "Simply Imóveis", telefone `(85) 98432-6253`, registro exibido como **CRECI 29379** (apenas no card de confiança da home + metadados de SEO).
8. **Uploads:** sempre corpo binário puro com metadados em query/header — `FormData` não funciona no edge-runtime self-hosted.
