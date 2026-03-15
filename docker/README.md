# Simply Imóveis - Deploy Docker Self-Hosted

Solução completa para deploy em Ubuntu 24.04 LTS com Docker.

---

## Arquitetura

```
                    Internet
                       │
                  ┌────▼────┐
                  │  Nginx   │  ← Host (porta 80/443)
                  │  (host)  │     Pode coexistir com outros sites
                  └──┬───┬──┘
                     │   │
        ┌────────────┘   └────────────┐
        ▼                             ▼
  / → Frontend                  /api/ → Kong
      127.0.0.1:3000                  127.0.0.1:8000
      (simply-frontend)              (simply-kong)
                                       │
                            ┌──────────┼──────────┬──────────┐
                            ▼          ▼          ▼          ▼
                        Auth       REST       Storage    Functions
                        :9999      :3000      :5000      :9000
                            └──────────┴──────────┴──────────┘
                                           │
                                     ┌─────▼─────┐
                                     │ PostgreSQL │
                                     │ :5432      │
                                     │ (interno)  │
                                     └───────────┘
```

**IMPORTANTE**: O stack Docker roda em `127.0.0.1` (localhost).
A exposição pública via domínio depende do **nginx do host**, que é configurado separadamente.

---

## Pré-requisitos

- Ubuntu 24.04 LTS (ou compatível)
- Acesso root (sudo)
- 2GB+ RAM, 20GB+ disco
- Portas 80, 443 livres (para SSL)
- Domínio apontando para o IP do servidor (para SSL)

---

## Instalação do Zero

```bash
# 1. Clone o repositório
git clone https://github.com/seu-usuario/simply-imoveis.git
cd simply-imoveis/docker

# 2. Execute o instalador
sudo bash install.sh

# Opções:
sudo bash install.sh --clean      # limpa instalação anterior
sudo bash install.sh --skip-ssl   # pula SSL
```

O instalador:
1. Instala Docker Engine e Compose
2. Copia projeto para `/opt/simply-imoveis`
3. Gera JWT_SECRET, POSTGRES_PASSWORD, ANON_KEY, SERVICE_ROLE_KEY
4. Pede interativamente: domínio, SMTP, Groq, Telegram
5. Cria admin
6. Build e deploy de todos os containers
7. Aplica schema, migrations, policies e triggers
8. Cria storage buckets
9. **Valida o stack interno** (containers + endpoints locais + banco)
10. Opcionalmente configura SSL + nginx do host

**Após a instalação, o stack está acessível APENAS em 127.0.0.1.**

---

## Endpoints

| Serviço | Endereço local | Observação |
|---|---|---|
| Frontend | `http://127.0.0.1:3000` | SPA React |
| Admin | `http://127.0.0.1:3000/admin` | Painel admin |
| Gateway API | `http://127.0.0.1:8000` | Kong (Auth, REST, Storage, Functions) |
| PostgreSQL | `127.0.0.1:5432` | Banco de dados |
| URL pública | `https://seudominio.com.br` | **Requer nginx do host configurado** |

---

## Integração com Nginx do Host

O stack Docker roda em `127.0.0.1`. Para expor via domínio público, configure o nginx do host como reverse proxy.

### Passo a passo

```bash
# 1. Rode o setup automático (recomendado)
cd /opt/simply-imoveis/docker
sudo bash setup-ssl.sh

# Ou configure manualmente:

# 2. Copie o template
sudo cp nginx-site.conf /etc/nginx/sites-available/simplyimoveis.conf

# 3. Edite o domínio
sudo nano /etc/nginx/sites-available/simplyimoveis.conf
# Substitua DOMINIO.COM.BR pelo seu domínio real

# 4. Ative o site (sem desativar outros!)
sudo ln -sf /etc/nginx/sites-available/simplyimoveis.conf /etc/nginx/sites-enabled/

# 5. Teste e recarregue
sudo nginx -t
sudo systemctl reload nginx

# 6. SSL com Certbot
sudo certbot --nginx -d seudominio.com.br -d www.seudominio.com.br

# 7. Valide a exposição pública
cd /opt/simply-imoveis/docker
bash validate-install.sh --public
```

### Coexistência com outros sites

O nginx do host pode servir múltiplos sites simultaneamente:
- Cada `server_name` é independente
- O Simply Imóveis usa apenas o domínio configurado
- Outros sites (ex: financeai em :8080) continuam funcionando
- **NÃO** remova o `default` site nem outros configs existentes

### Verificação rápida

```bash
# Stack interno OK?
curl -s http://127.0.0.1:3000 | head -5

# Gateway OK?
curl -s http://127.0.0.1:8000/auth/v1/settings -H "apikey: SUA_ANON_KEY" | head -5

# Nginx do host tem a config?
sudo nginx -T 2>/dev/null | grep server_name

# URL pública responde com Simply Imóveis?
curl -sI https://seudominio.com.br | head -5
```

---

## Variáveis de Ambiente

| Variável | Obrigatória | Descrição |
|---|---|---|
| `SITE_DOMAIN` | ✅ | Domínio do site |
| `POSTGRES_PASSWORD` | ✅ Auto | Senha PostgreSQL |
| `JWT_SECRET` | ✅ Auto | Segredo JWT |
| `ANON_KEY` | ✅ Auto | Chave pública |
| `SERVICE_ROLE_KEY` | ✅ Auto | Chave de serviço |
| `SMTP_USER` | ⚠️ | Email para envio |
| `SMTP_PASS` | ⚠️ | Senha do email |
| `GROQ_API_KEY` | ⚠️ | Chat IA ([console.groq.com](https://console.groq.com/keys)) |
| `TELEGRAM_BOT_TOKEN` | Opcional | Bot via @BotFather |
| `TELEGRAM_CHAT_ID` | Opcional | ID do chat |

---

## Comandos de Operação

```bash
cd /opt/simply-imoveis/docker

bash status.sh                      # status dos containers
bash logs.sh                        # logs de todos
bash logs.sh functions              # logs functions
bash validate-install.sh            # validar stack INTERNO
bash validate-install.sh --public   # validar exposição PÚBLICA
bash redeploy.sh                    # rebuild frontend + functions
bash redeploy.sh --full             # rebuild tudo
bash backup.sh                      # backup banco + storage
bash restore.sh /path/backup.gz     # restaurar
bash reset-db.sh                    # resetar banco (com backup)
bash full-wipe.sh                   # apagar containers e dados
bash create-admin.sh e@mail.com s   # criar/resetar admin
sudo bash setup-ssl.sh              # configurar nginx + SSL

# Docker Compose direto
docker compose up -d
docker compose down
docker compose restart
docker compose logs --tail=50 -f
```

---

## Comandos de Diagnóstico

```bash
# 1. Containers rodando?
docker ps --filter "name=simply-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# 2. Frontend local responde?
curl -sI http://127.0.0.1:3000 | head -3

# 3. Gateway local responde?
curl -sI http://127.0.0.1:8000/auth/v1/settings -H "apikey: SUA_ANON_KEY" | head -3

# 4. Nginx do host - configuração completa
sudo nginx -T

# 5. Qual site está respondendo na porta 80/443?
curl -sI http://localhost | head -5

# 6. Validação completa
cd /opt/simply-imoveis/docker
bash validate-install.sh --public
```

---

## Troubleshooting

| Problema | Solução |
|---|---|
| URL pública mostra outro site | Configurar nginx do host: `sudo bash setup-ssl.sh` |
| Functions boot error | `bash sync-functions.sh ... && docker compose restart functions` |
| Auth 502 | `bash sync-db-passwords.sh && docker compose restart auth` |
| RLS/permissão | `psql < sql/selfhosted-admin-recovery.sql` |
| Admin não loga | `bash create-admin.sh email senha` |
| Banco corrompido | `bash reset-db.sh` |
| Tudo quebrado | `bash full-wipe.sh && bash install.sh` |

---

## Checklist de Validação

- [ ] `docker ps --filter "name=simply-"` — todos running
- [ ] `curl http://127.0.0.1:3000` — frontend carrega
- [ ] `curl http://127.0.0.1:8000/auth/v1/settings` — auth responde
- [ ] `bash validate-install.sh` — 0 failures
- [ ] Login em `http://127.0.0.1:3000/admin` funciona
- [ ] Nginx do host configurado para o domínio
- [ ] `bash validate-install.sh --public` — URL pública correta
- [ ] `https://seudominio.com.br` carrega o Simply Imóveis (não outro sistema)
