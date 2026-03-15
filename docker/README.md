# Simply Imóveis - Deploy Docker Self-Hosted

Solução completa para deploy em Ubuntu 24.04 LTS com Docker.

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
9. Valida instalação
10. Opcionalmente configura SSL

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

## Como Configurar Telegram

1. Abra Telegram → `@BotFather` → `/newbot`
2. Copie o token → `TELEGRAM_BOT_TOKEN`
3. Envie mensagem ao bot
4. Acesse `https://api.telegram.org/bot<TOKEN>/getUpdates`
5. Copie `chat.id` → `TELEGRAM_CHAT_ID`

---

## Comandos de Operação

```bash
cd /opt/simply-imoveis/docker

bash status.sh                    # status dos serviços
bash logs.sh                      # logs de todos
bash logs.sh functions             # logs functions
bash validate-install.sh          # validar saúde
bash redeploy.sh                   # rebuild frontend + functions
bash redeploy.sh --full            # rebuild tudo
bash backup.sh                    # backup banco + storage
bash restore.sh /path/backup.gz   # restaurar
bash reset-db.sh                   # resetar banco (com backup)
bash full-wipe.sh                  # apagar TUDO
bash create-admin.sh e@mail.com s  # criar/resetar admin
sudo bash setup-ssl.sh             # configurar SSL

# Docker Compose direto
docker compose up -d
docker compose down
docker compose restart
docker compose logs --tail=50 -f
```

---

## Arquitetura

```
Nginx (host) :80/:443
├── / → Frontend (:3000)
└── /api/ → Kong (:8000)
    ├── /auth/v1/ → GoTrue (:9999)
    ├── /rest/v1/ → PostgREST (:3000)
    ├── /storage/v1/ → Storage (:5000)
    └── /functions/v1/ → Edge Runtime (:9000)
        ├── chat
        ├── admin-crud
        ├── create-admin-user
        └── notify-telegram
All → PostgreSQL (:5432, interno)
```

Containers separados por design: rebuild independente, restart isolado, logs separados.

---

## SSL

```bash
sudo bash setup-ssl.sh
```

Pré-requisito: DNS apontando para o servidor. Usa Nginx + Let's Encrypt.

---

## Backup

```bash
# Manual
bash backup.sh

# Automático (crontab -e)
0 2 * * * /opt/simply-imoveis/docker/backup.sh
```

---

## Troubleshooting

| Problema | Solução |
|---|---|
| Functions boot error | `bash sync-functions.sh ... && docker compose restart functions` |
| Auth 502 | `bash sync-db-passwords.sh && docker compose restart auth` |
| RLS/permissão | `psql < sql/selfhosted-admin-recovery.sql` |
| Admin não loga | `bash create-admin.sh email senha` |
| Banco corrompido | `bash reset-db.sh` |
| Tudo quebrado | `bash full-wipe.sh && bash install.sh` |

---

## Checklist de Validação

- [ ] `bash status.sh` — todos running
- [ ] `bash validate-install.sh` — 0 failures
- [ ] `http://localhost:3000` carrega
- [ ] `http://localhost:3000/admin` — login funciona
- [ ] Criar imóvel no admin
- [ ] Criar inquilino no admin
- [ ] Chat IA responde (se GROQ_API_KEY)
- [ ] SSL funciona (se configurado)
