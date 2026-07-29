-- Idempotente de propósito: em CI e nos testes de integração esta migration
-- roda mais de uma vez contra o mesmo banco.
CREATE TABLE IF NOT EXISTS tasks (
    id         BIGSERIAL PRIMARY KEY,
    title      TEXT        NOT NULL CHECK (length(trim(title)) > 0 AND length(title) <= 200),
    status     TEXT        NOT NULL DEFAULT 'todo' CHECK (status IN ('todo', 'doing', 'done')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Índice para o filtro por status que vem depois. Sem ele, o plano é seq scan
-- na tabela inteira — coisa que só aparece no Grafana da Fase 8, tarde demais.
CREATE INDEX IF NOT EXISTS tasks_status_idx ON tasks (status);
