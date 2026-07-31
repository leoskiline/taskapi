-- Todo up precisa de um down. Migration sem rollback é deploy sem volta —
-- e a Fase 7 (GitOps) vai depender de conseguir reverter.
DROP INDEX IF EXISTS tasks_status_idx;
DROP TABLE IF EXISTS tasks;
