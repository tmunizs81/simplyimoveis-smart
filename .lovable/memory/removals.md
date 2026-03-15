Registro de problemas resolvidos e decisões técnicas para não repetir.

## RLS "violates row-level security" na VPS (2026-03-15)
- CAUSA RAIZ: `PGRST_DB_USE_LEGACY_GUCS: "false"` fazia PostgREST NÃO setar `request.jwt.claim.sub`
- auth.uid() retornava NULL → toda checagem RLS falhava
- FIX: mudou para `PGRST_DB_USE_LEGACY_GUCS: "true"` no docker-compose.yml
- NUNCA usar legacy_gucs=false em self-hosted Supabase

## Edge Function 404 na VPS (2026-03-15)
- CAUSA RAIZ: dynamic `import()` não funciona corretamente no supabase/edge-runtime self-hosted
- FIX: render-functions-main.sh agora gera importações ESTÁTICAS no main/index.ts
- NUNCA usar dynamic import() no router principal de edge functions self-hosted

## "permission denied for table" na VPS (2026-03-15)  
- CAUSA: GRANTs não aplicados após init do banco
- FIX: sync-db-passwords.sh aplica GRANT ALL em todas tabelas/sequences/routines do schema public
