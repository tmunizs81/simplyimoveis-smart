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
- Priorizar scripts em /docker com leitura segura de .env (sem source .env)
- Fluxo: install.sh → create-admin.sh → login /admin

## Scripts Docker
- install.sh — instalador completo (--clean, --skip-ssl)
- full-wipe.sh — limpeza total (--force)
- reset-db.sh — reset apenas do banco
- redeploy.sh — rebuild sem perder dados (--full)
- update.sh / update-from-github.sh — atualização
- validate-install.sh — validação completa
- status.sh — status dos serviços
- logs.sh — visualizar logs
- fix-vps-admin.sh — recovery completo
- backup.sh / restore.sh — backup e restauração

## Lições aprendidas
- NUNCA usar SQL direto em auth.users para criar usuários — usar GoTrue Admin API
- NUNCA usar variável `UID` em bash (é readonly)
- NUNCA usar `source .env` — usar read_env() com grep
- Sempre usar `-h 127.0.0.1` no psql dentro do container
- sync-db-passwords.sh dropa e recria auth.uid()/role()/email() como supabase_auth_admin
- Edge functions precisam de `export default handler` para runtime self-host
- Todas as mutations admin via `adminCrud.ts` → edge function `admin-crud` (bypassa RLS)

## Design
- Gradiente laranja/dourado (gradient-primary), font display, cards rounded-2xl shadow-xl
- Semantic tokens do Tailwind (bg-card, text-foreground, etc.)
