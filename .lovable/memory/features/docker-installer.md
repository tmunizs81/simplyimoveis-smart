Scripts Docker self-hosted revisados para evitar bugs conhecidos.

- sync-db-passwords.sh: usa arquivo SQL temporário, filtra enums com `typtype='e' AND typrelid=0` (evita erro de row type), não derruba schema `auth` automaticamente, e força rerun de migrações GoTrue quando `auth.users` sumir (truncate em `schema_migrations/gorp_migrations`)
- create-admin.sh: 100% SQL direto (sem Auth API), usa PGOPTIONS e valida `auth.users` antes de criar admin
- install.sh: fluxo completo com GROQ/Telegram interativo, re-sync pós GoTrue, admin pré-criado, SSL integrado
- notify-telegram edge function: suporta duas rotas (connector com `TELEGRAM_API_KEY` + `LOVABLE_API_KEY` OU bot direto com `TELEGRAM_BOT_TOKEN`)
- docker-compose.yml: `GOTRUE_DB_NAMESPACE=auth`, `DB_NAMESPACE=auth` e `search_path=auth` no `GOTRUE_DB_DATABASE_URL` para evitar lookup de `users` no schema errado
- validate-install.sh: checa `auth.users`, fluxo de login (espera 400, não 500), containers e REST
