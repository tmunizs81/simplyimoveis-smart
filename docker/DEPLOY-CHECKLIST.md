# Simply Imóveis — Checklist de Deploy VPS

## Pré-requisitos

- [ ] Ubuntu 22.04+ ou Debian 12+
- [ ] 2GB RAM mínimo (4GB recomendado)
- [ ] Docker Engine 24+ e Docker Compose v2
- [ ] Domínio apontando para o IP do servidor (DNS A record)
- [ ] Portas 80 e 443 liberadas no firewall

---

## 1. Variáveis de Ambiente Obrigatórias

Arquivo: `docker/.env` (copie de `.env.example`)

| Variável | Descrição | Geração |
|---|---|---|
| `SITE_DOMAIN` | Domínio do site (ex: `simplyimoveis.com.br`) | Manual |
| `POSTGRES_PASSWORD` | Senha do PostgreSQL | Auto (`install.sh`) |
| `POSTGRES_USER` | Usuário PostgreSQL | Padrão: `supabase_admin` |
| `POSTGRES_DB` | Nome do banco | Padrão: `simply_db` |
| `JWT_SECRET` | Segredo para assinar tokens JWT (min 32 chars) | Auto (`install.sh`) |
| `ANON_KEY` | JWT com role=anon, assinado com JWT_SECRET | Auto (`install.sh`) |
| `SERVICE_ROLE_KEY` | JWT com role=service_role, assinado com JWT_SECRET | Auto (`install.sh`) |
| `SMTP_HOST` | Servidor SMTP | Manual |
| `SMTP_PORT` | Porta SMTP | Padrão: `587` |
| `SMTP_USER` | Email SMTP | Manual |
| `SMTP_PASS` | Senha SMTP (App Password para Gmail) | Manual |
| `SMTP_SENDER_NAME` | Nome do remetente | Padrão: `Simply Imóveis` |
| `SMTP_ADMIN_EMAIL` | Email do admin para envios | Manual |
| `GROQ_API_KEY` | API key para chat IA (groq.com) | Manual |

### Variáveis Opcionais

| Variável | Descrição |
|---|---|
| `TELEGRAM_BOT_TOKEN` | Token do bot Telegram |
| `TELEGRAM_CHAT_ID` | Chat ID para notificações |
| `KONG_HTTP_PORT` | Porta do Kong (padrão: `8000`) |
| `FRONTEND_PORT` | Porta do frontend (padrão: `3000`) |

### ⚠️ Regra Crítica: Consistência JWT

`ANON_KEY` e `SERVICE_ROLE_KEY` **devem** ser JWTs assinados com o **mesmo** `JWT_SECRET`.
Se alterar o `JWT_SECRET`, regenere as chaves com:

```bash
bash fix-auth-keys.sh email@admin.com senha
```

---

## 2. Instalação Automática (Recomendado)

```bash
cd /caminho/do/projeto
sudo bash docker/install.sh
```

O `install.sh` faz tudo automaticamente:
1. Instala dependências do host (Docker, Nginx, Certbot)
2. Gera credenciais seguras (JWT_SECRET, POSTGRES_PASSWORD, chaves JWT)
3. Configura Kong API Gateway
4. Sincroniza Edge Functions
5. Sobe PostgreSQL e executa bootstrap (schema, roles, grants)
6. Sobe todos os serviços
7. Cria o primeiro usuário admin
8. Opcionalmente configura SSL

---

## 3. Instalação Manual (Passo a Passo)

### 3.1 Preparar .env
```bash
cd docker
cp .env.example .env
# Edite .env com seus valores
```

### 3.2 Gerar chaves JWT
```bash
# Se JWT_SECRET já existe no .env:
bash fix-auth-keys.sh admin@email.com senha123

# Ou manualmente com Node.js:
node -e "
const c=require('crypto');
const jwt=(role,secret)=>{
  const h=Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url');
  const p=Buffer.from(JSON.stringify({role,iss:'supabase',iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+315360000})).toString('base64url');
  const s=c.createHmac('sha256',secret).update(h+'.'+p).digest('base64url');
  return h+'.'+p+'.'+s;
};
const secret='SEU_JWT_SECRET';
console.log('ANON_KEY='+jwt('anon',secret));
console.log('SERVICE_ROLE_KEY='+jwt('service_role',secret));
"
```

### 3.3 Renderizar Kong config
```bash
bash render-kong-config.sh
```

### 3.4 Sincronizar Edge Functions
```bash
bash sync-functions.sh ../supabase/functions volumes/functions
```

### 3.5 Subir banco e bootstrap
```bash
docker compose up -d db
# Aguardar até o banco estar saudável
bash bootstrap-db.sh
bash sync-db-passwords.sh
```

### 3.6 Subir todos os serviços
```bash
docker compose up -d --build
# Aguardar ~30s para GoTrue migrar o schema auth
```

### 3.7 Criar admin
```bash
bash create-admin.sh admin@email.com senha123
```

### 3.8 Configurar SSL
```bash
sudo bash setup-ssl.sh
```

---

## 4. Arquitetura dos Serviços

```
Internet → Nginx (443/80) → Kong (:8000) → GoTrue (:9999)
                                          → PostgREST (:3000)
                                          → Storage (:5000)
                                          → Edge Functions (:9000)
                           → Frontend (:3000 interno)
                           
Kong → PostgreSQL (:5432)
```

### Variáveis no Frontend (build-time)
- `VITE_SUPABASE_URL` = `https://{SITE_DOMAIN}/api` (Nginx faz proxy `/api/` → Kong)
- `VITE_SUPABASE_PUBLISHABLE_KEY` = valor de `ANON_KEY`

### Variáveis nas Edge Functions (runtime)
- `SUPABASE_URL` = `http://kong:8000` (rede interna Docker)
- `SUPABASE_SERVICE_ROLE_KEY` = valor de `SERVICE_ROLE_KEY`
- `SUPABASE_ANON_KEY` = valor de `ANON_KEY`

---

## 5. Database Setup

### Schema automático
O arquivo `docker/volumes/db/init/01-schema.sql` roda automaticamente na primeira inicialização do container `db`.

### Tabelas principais
- `properties`, `property_media` — imóveis
- `contact_submissions`, `scheduled_visits` — contatos
- `leads`, `sales`, `sales_documents` — vendas
- `tenants`, `tenant_documents` — inquilinos
- `rental_contracts`, `contract_documents` — contratos
- `financial_transactions` — financeiro
- `property_inspections`, `inspection_media` — vistorias
- `user_roles` — controle de acesso (admin/moderator/user)
- `property_code_sequences` — códigos automáticos

### Roles PostgreSQL necessárias
- `supabase_admin` — superusuário
- `supabase_auth_admin` — owner do schema auth
- `supabase_storage_admin` — owner do schema storage
- `authenticator` — role de conexão do PostgREST
- `anon` — role para requisições não autenticadas
- `authenticated` — role para requisições autenticadas
- `service_role` — role com bypass de RLS

O script `sync-db-passwords.sh` configura todas as senhas e grants.

### Funções PostgreSQL
- `auth.uid()`, `auth.role()`, `auth.email()` — funções de contexto JWT
- `public.has_role(uuid, app_role)` — verifica role do usuário (SECURITY DEFINER)
- `public.generate_property_short_code()` — trigger para código do imóvel

---

## 6. Fluxo de Autenticação

1. Frontend chama `supabase.auth.signInWithPassword()` → Kong → GoTrue
2. GoTrue valida credenciais em `auth.users`, retorna JWT
3. Frontend armazena JWT no `localStorage` (persistSession: true)
4. Requisições admin vão para Edge Function `admin-crud`:
   - Frontend envia `Authorization: Bearer <access_token>`
   - Edge Function valida token com `supabase.auth.getUser(token)`
   - Verifica role admin em `public.user_roles` via service_role client
   - Executa operação com service_role (bypass RLS)

### Criação de admin
Sempre via GoTrue Admin API (nunca SQL direto em auth.users):
```bash
bash create-admin.sh email@admin.com senha123
```

---

## 7. Diagnóstico e Troubleshooting

### Health check completo
```bash
bash health-check.sh
```

### Comandos úteis
```bash
bash status.sh                      # Status dos containers
bash logs.sh                        # Logs de todos os serviços
docker compose logs --tail=50 auth  # Logs específicos do GoTrue
bash validate-install.sh            # Validação do stack
bash validate-install.sh --public   # Validação via domínio público
```

### Problemas comuns

| Problema | Causa | Solução |
|---|---|---|
| HTTP 401 no login | ANON_KEY/JWT_SECRET inconsistentes | `bash fix-auth-keys.sh email senha` |
| HTTP 401 na Admin API | SERVICE_ROLE_KEY incorreta | `bash fix-auth-keys.sh email senha` |
| "auth.users não existe" | GoTrue não migrou | Aguarde 30s ou `docker compose restart auth` |
| Login OK mas "sem role admin" | Falta registro em user_roles | `bash create-admin.sh email senha` |
| Edge functions 500 | Variáveis ausentes no container | Verificar `docker compose logs functions` |
| kong.yml desatualizado | Chaves foram alteradas sem re-render | `bash render-kong-config.sh && docker compose restart kong` |
| Frontend usa URL errada | VITE vars no build-time | `docker compose up -d --build frontend` |

### Regenerar tudo do zero
```bash
bash fix-auth-keys.sh email@admin.com senha123
# Regenera JWT keys, atualiza .env, kong.yml, reinicia containers, cria admin
```

---

## 8. Atualização

```bash
cd /opt/simply-imoveis/docker
bash update-from-github.sh
# Ou manualmente:
bash sync-functions.sh ../supabase/functions volumes/functions
bash render-kong-config.sh
docker compose up -d --build --remove-orphans
```

---

## 9. Backup e Restore

```bash
bash backup.sh              # Cria dump do banco
bash restore.sh backup.sql  # Restaura de um dump
```

---

## 10. Checklist Final Pós-Deploy

- [ ] `bash health-check.sh` sem erros
- [ ] Login em `https://dominio/admin` funciona
- [ ] Criar/editar imóvel no admin funciona
- [ ] Site público em `https://dominio` carrega
- [ ] Chat IA responde (requer GROQ_API_KEY)
- [ ] Upload de fotos funciona (Storage)
- [ ] SSL válido (`https://` sem avisos)
