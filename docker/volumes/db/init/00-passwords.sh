#!/bin/bash
# ============================================================
# Define senhas dos roles internos do Supabase durante init
# Roda automaticamente na primeira inicialização do PostgreSQL
# ============================================================
set -e

echo "🔐 Configurando senhas dos roles internos..."

psql -v ON_ERROR_STOP=1 --username postgres --dbname "${POSTGRES_DB:-simply_db}" <<-EOSQL
  -- Definir senhas para todos os roles internos
  ALTER ROLE supabase_admin WITH PASSWORD '${POSTGRES_PASSWORD}';
  ALTER ROLE supabase_auth_admin WITH PASSWORD '${POSTGRES_PASSWORD}';
  ALTER ROLE authenticator WITH PASSWORD '${POSTGRES_PASSWORD}';
  ALTER ROLE supabase_storage_admin WITH PASSWORD '${POSTGRES_PASSWORD}';

  -- Garantir extensão pgcrypto
  CREATE EXTENSION IF NOT EXISTS pgcrypto;

  -- Garantir schema auth existe com owner correto
  DO \$\$
  BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth') THEN
      CREATE SCHEMA auth AUTHORIZATION supabase_auth_admin;
    ELSE
      ALTER SCHEMA auth OWNER TO supabase_auth_admin;
    END IF;
  END \$\$;

  -- Permissões no schema auth
  GRANT USAGE ON SCHEMA auth TO supabase_auth_admin, authenticator, anon, authenticated, service_role;
  GRANT CREATE ON SCHEMA auth TO supabase_auth_admin;
  GRANT ALL ON ALL TABLES IN SCHEMA auth TO supabase_auth_admin;
  GRANT ALL ON ALL SEQUENCES IN SCHEMA auth TO supabase_auth_admin;
  GRANT ALL ON ALL ROUTINES IN SCHEMA auth TO supabase_auth_admin;
  GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA auth TO authenticator;
  GRANT USAGE ON ALL SEQUENCES IN SCHEMA auth TO authenticator;

  -- Permissões no schema public
  GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role, authenticator;
  GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon, authenticated;
  GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
  GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;
  GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;
EOSQL

echo "✅ Senhas e permissões configuradas!"
