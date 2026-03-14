# Simply Imóveis - Instalação Docker (Produção)

## Requisitos
- VPS Ubuntu 24.04 LTS (mín. 2GB RAM, 20GB disco)
- Domínio apontando para o IP da VPS (DNS tipo A)
- Acesso root (sudo)

## Instalação (1 comando)

```bash
# Conecte na VPS e execute:
git clone https://github.com/tmunizs81/simplyimoveis-smart.git /opt/simply-imoveis
cd /opt/simply-imoveis/docker
sudo bash deploy.sh
```

O script faz **tudo automaticamente**:
1. ✅ Instala Docker, Nginx, Certbot
2. ✅ Clona o repositório
3. ✅ Gera chaves JWT (ANON_KEY, SERVICE_ROLE_KEY)
4. ✅ Gera senha segura do banco
5. ✅ Configura e inicia 7 containers Docker
6. ✅ Configura Nginx como proxy reverso
7. ✅ Gera certificado SSL (HTTPS) com renovação automática
8. ✅ Cria usuário admin com role
9. ✅ Configura backup diário automático (2h)

### O que o script pergunta:
- **Domínio** (padrão: simplyimoveis.com.br)
- **Email e senha do admin**
- **GROQ API Key** (obrigatória para o chat — https://console.groq.com/keys)
- **Telegram Bot Token + Chat ID** (opcional)

## Atualizar o Sistema

```bash
cd /opt/simply-imoveis/docker
sudo bash update.sh
```

## Comandos Úteis

```bash
cd /opt/simply-imoveis/docker

docker compose ps              # Status dos containers
docker compose logs -f         # Ver todos os logs
docker compose logs -f auth    # Logs da autenticação
docker compose logs -f frontend # Logs do frontend
docker compose restart         # Reiniciar tudo
docker compose down            # Parar tudo
docker compose up -d           # Iniciar tudo
```

## Backup & Restore

```bash
# Backup manual
bash backup.sh

# Ver backups
ls -la /opt/simply-imoveis/backups/

# Restaurar
bash restore.sh /opt/simply-imoveis/backups/simply-backup-YYYY-MM-DD_HHMM.sql.gz
```

O backup diário automático roda às 2h e mantém os últimos 30 dias.

## Configurar SMTP (Email)

Edite o `.env` e reinicie o auth:

```bash
nano /opt/simply-imoveis/docker/.env
# Preencha: SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS
docker compose restart auth
```

## Arquitetura

```
Internet → Nginx (443/SSL) → Frontend (:3000)
                            → Kong API Gateway (:8000)
                                ├── GoTrue Auth (:9999)
                                ├── PostgREST (:3000)
                                ├── Storage API (:5000)
                                └── Edge Functions (:9000)
                                      ├── chat (Luma IA)
                                      ├── notify-telegram
                                      └── create-admin-user
                            → PostgreSQL (:5432, interno)
```

## Portas

| Serviço | Porta | Acesso |
|---------|-------|--------|
| Frontend | 3000 | Via Nginx |
| Kong (API) | 8000 | Via Nginx |
| PostgreSQL | 5432 | Apenas localhost |

## Troubleshooting

```bash
# Container não inicia
docker compose logs <nome-do-servico>

# Banco não conecta
docker compose exec db pg_isready -U supabase_admin -d simply_db

# Verificar Nginx
nginx -t
systemctl status nginx

# Renovar SSL
certbot renew --dry-run

# Resetar tudo (CUIDADO: apaga dados)
docker compose down -v
docker compose up -d
```
