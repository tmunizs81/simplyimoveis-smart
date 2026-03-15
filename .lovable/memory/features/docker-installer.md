Scripts Docker self-hosted revisados para evitar bugs conhecidos.

- sync-db-passwords.sh: usa arquivo SQL temporário (evita problemas de escape), filtra apenas enums no ALTER TYPE (exclui row types de tabelas), recria schema auth do zero se auth.users não existir
- create-admin.sh: 100% SQL direto (não depende da Auth API), usa PGOPTIONS para passar parâmetros com segurança
- install.sh: fluxo completo com GROQ/Telegram interativo, re-sync pós GoTrue, admin pré-criado, SSL integrado
- validate-install.sh: checa auth.users, fluxo de login (espera 400, não 500), containers e REST
- Nunca usar ALTER TYPE em row types de tabelas (causa "is a table's row type" error)
- GOTRUE_DB_NAMESPACE=auth obrigatório no docker-compose.yml
