-- ============================================================
-- Simply Imóveis - Init SQL mínimo (intencional)
-- A criação completa do schema é feita por docker/bootstrap-db.sh
-- ============================================================

DO $$
BEGIN
  RAISE NOTICE '01-schema.sql: init mínimo executado. Schema completo via bootstrap-db.sh';
END
$$;
