# Memory: index.md
Updated: now

Projeto Simply Imóveis — sistema imobiliário com admin panel, self-hosted via Docker.

## Stack
- React + Vite + Tailwind + TypeScript (frontend)
- Supabase self-hosted via Docker (GoTrue, PostgREST, Kong, Storage, Edge Functions)
- Nginx reverse proxy com SSL (Certbot)

## Arquitetura Docker
- docker-compose.yml com: db, auth (GoTrue), rest (PostgREST), storage, kong, functions (Deno), frontend
- VITE_SUPABASE_URL = https://{SITE_DOMAIN}/api (nginx faz proxy /api/ → kong:8000)
- Edge functions copiadas para docker/volumes/functions/ pelo sync-functions.sh
- Kong config renderizado via render-kong-config.sh (template com __ANON_KEY__ e __SERVICE_ROLE_KEY__)
- SQL executado via STDIN do host (`< sql/file.sql`), NUNCA via `psql -f` dentro do container
- Fluxo: install.sh → bootstrap-db.sh → validate-install.sh → create-admin.sh

## Lições aprendidas
- NUNCA usar `psql -f arquivo` via docker exec (arquivo não existe dentro do container)
- NUNCA usar SQL direto em auth.users para criar usuários — usar GoTrue Admin API
- NUNCA usar variável `UID` em bash (é readonly)
- Sempre usar `-h 127.0.0.1` no psql dentro do container
- Storage policies usam has_role_text(uuid,text) para evitar dependência do enum app_role
- Bootstrap pipeline: passwords → core SQL → validate → start storage → storage SQL

## Design
- Gradiente laranja/dourado (gradient-primary), font display, cards rounded-2xl shadow-xl
- Semantic tokens do Tailwind (bg-card, text-foreground, etc.)
