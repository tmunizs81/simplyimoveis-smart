Scripts Docker self-hosted v5 — reescritos do zero.

Mudanças principais vs versões anteriores:
- Todos os scripts usam `postgres` superuser (sem PGPASSWORD, sem auth failure)
- sync-db-passwords.sh: inline SQL (sem arquivo temporário), filtro de enums com `typrelid=0`
- create-admin.sh: valores inline no SQL (sem PGOPTIONS/current_setting), valida auth.users antes
- Nunca usar ALTER TYPE em row types de tabelas (causa "is a table's row type")
- auth.identities.id é UUID (nunca cast para text)
- docker-compose.yml: `GOTRUE_DB_NAMESPACE=auth`, `DB_NAMESPACE=auth`, `search_path=auth` no DB URL
- notify-telegram: dual-mode (connector via LOVABLE_API_KEY ou bot direto via TELEGRAM_BOT_TOKEN)
