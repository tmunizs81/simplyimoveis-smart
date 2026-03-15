#!/bin/bash
# ============================================================
# Define senhas dos roles internos do Supabase durante init
# Roda automaticamente na primeira inicialização do PostgreSQL
# IMPORTANTE: Usa heredoc SEM aspas para expandir variáveis bash
# ============================================================
set -e

echo "🔐 Configurando senhas dos roles internos..."

# Escapar a senha para uso seguro em SQL
ESCAPED_PASS=$(printf '%s' "${POSTGRES_PASSWORD}" | sed "s/'/''/g")

psql -v ON_ERROR_STOP=0 --username postgres --dbname "${POSTGRES_DB:-simply_db}" <<EOSQL

-- Tentar definir senhas (ignora erro se role não existir ainda)
DO \$\$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_admin') THEN
    EXECUTE 'ALTER ROLE supabase_admin WITH PASSWORD ''${ESCAPED_PASS}''';
    RAISE NOTICE 'supabase_admin: senha definida';
  END IF;

  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
    EXECUTE 'ALTER ROLE supabase_auth_admin WITH PASSWORD ''${ESCAPED_PASS}''';
    RAISE NOTICE 'supabase_auth_admin: senha definida';
  END IF;

  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticator') THEN
    EXECUTE 'ALTER ROLE authenticator WITH PASSWORD ''${ESCAPED_PASS}''';
    RAISE NOTICE 'authenticator: senha definida';
  END IF;

  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_storage_admin') THEN
    EXECUTE 'ALTER ROLE supabase_storage_admin WITH PASSWORD ''${ESCAPED_PASS}''';
    RAISE NOTICE 'supabase_storage_admin: senha definida';
  END IF;
END \$\$;

-- Garantir extensão pgcrypto
CREATE EXTENSION IF NOT EXISTS pgcrypto;

EOSQL

echo "✅ Senhas dos roles configuradas!"