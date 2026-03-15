#!/bin/bash
# ============================================================
# Define senhas dos roles internos do Supabase durante init
# Roda automaticamente na primeira inicialização do PostgreSQL
# ============================================================
set -euo pipefail

echo "🔐 Configurando senhas dos roles internos..."

psql -v ON_ERROR_STOP=1 \
  --username postgres \
  --dbname "${POSTGRES_DB:-simply_db}" \
  --set=postgres_password="${POSTGRES_PASSWORD}" <<'EOSQL'
  -- Garantir extensão pgcrypto
  CREATE EXTENSION IF NOT EXISTS pgcrypto;

  -- Ajustar senha somente dos roles que existirem
  DO $$
  BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_admin') THEN
      EXECUTE format('ALTER ROLE supabase_admin WITH PASSWORD %L', :'postgres_password');
    ELSE
      RAISE NOTICE 'Role supabase_admin não existe, pulando';
    END IF;

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
      EXECUTE format('ALTER ROLE supabase_auth_admin WITH PASSWORD %L', :'postgres_password');
    ELSE
      RAISE NOTICE 'Role supabase_auth_admin não existe, pulando';
    END IF;

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticator') THEN
      EXECUTE format('ALTER ROLE authenticator WITH PASSWORD %L', :'postgres_password');
    ELSE
      RAISE NOTICE 'Role authenticator não existe, pulando';
    END IF;

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_storage_admin') THEN
      EXECUTE format('ALTER ROLE supabase_storage_admin WITH PASSWORD %L', :'postgres_password');
    ELSE
      RAISE NOTICE 'Role supabase_storage_admin não existe, pulando';
    END IF;
  END $$;

  -- Garantir schema auth com owner correto quando o role existir
  DO $$
  BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
      IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth') THEN
        CREATE SCHEMA auth AUTHORIZATION supabase_auth_admin;
      ELSE
        ALTER SCHEMA auth OWNER TO supabase_auth_admin;
      END IF;
    ELSE
      RAISE NOTICE 'Role supabase_auth_admin não existe, pulando ajuste de owner do schema auth';
    END IF;
  END $$;
EOSQL

echo "✅ Senhas dos roles configuradas (com fallback seguro)!"