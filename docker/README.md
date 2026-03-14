# Simply Imóveis - Instalação Docker

## Requisitos
- Ubuntu 24.04 LTS
- Docker + Docker Compose
- Nginx (já instalado na VPS)
- Domínio apontando para o IP da VPS

## Instalação Rápida

```bash
# 1. Clone o repositório
git clone <repo-url> /opt/simply-imoveis
cd /opt/simply-imoveis/docker

# 2. Configure o ambiente
cp .env.example .env
nano .env   # Preencha SITE_DOMAIN, SMTP, GROQ_API_KEY

# 3. Gere as chaves JWT
bash generate-keys.sh

# 4. Execute o instalador
sudo bash install.sh

# 5. Crie o primeiro admin
bash create-admin.sh admin@seudominio.com suaSenhaForte123

# 6. Configure o Nginx
sudo cp nginx-site.conf /etc/nginx/sites-available/simplyimoveis.conf
sudo ln -s /etc/nginx/sites-available/simplyimoveis.conf /etc/nginx/sites-enabled/
# Edite o arquivo para ajustar o domínio
sudo nano /etc/nginx/sites-available/simplyimoveis.conf
sudo nginx -t && sudo systemctl reload nginx

# 7. SSL com Certbot
sudo certbot --nginx -d seudominio.com -d www.seudominio.com
```

## Comandos Úteis

```bash
cd /opt/simply-imoveis/docker

# Ver logs
docker compose logs -f

# Reiniciar
docker compose restart

# Parar
docker compose down

# Atualizar (após git pull)
docker compose up -d --build frontend
```

## Backup & Restore

```bash
# Backup manual
bash backup.sh

# Agendar backup diário às 2h (cron)
echo "0 2 * * * /opt/simply-imoveis/docker/backup.sh >> /var/log/simply-backup.log 2>&1" | sudo crontab -

# Listar backups
ls -la /opt/simply-imoveis/backups/

# Restaurar
bash restore.sh /opt/simply-imoveis/backups/simply-backup-2026-03-14_0200.sql.gz
```

## Portas Utilizadas

| Serviço | Porta Interna | Observação |
|---------|---------------|------------|
| Frontend | 3000 | Via Nginx |
| Kong (API) | 8000 | Via Nginx |
| PostgreSQL | 5432 | Apenas localhost |

## Estrutura

```
docker/
├── docker-compose.yml      # Orquestração dos containers
├── Dockerfile              # Build do frontend
├── .env.example            # Template de configuração
├── nginx-frontend.conf     # Nginx interno do container
├── nginx-site.conf         # Config do Nginx da VPS
├── install.sh              # Instalador automático
├── generate-keys.sh        # Gerador de chaves JWT
├── create-admin.sh         # Criação do admin
├── backup.sh               # Script de backup
├── restore.sh              # Script de restauração
└── volumes/
    ├── db/init/             # SQL de inicialização
    ├── kong/                # Config do API Gateway
    └── functions/           # Edge Functions
```
