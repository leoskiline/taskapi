package task

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Store é a porta de persistência. O handler depende desta interface, não do
// Postgres — é o que permite testar os handlers sem subir banco nenhum.
type Store interface {
	List(ctx context.Context) ([]Task, error)
	Get(ctx context.Context, id int64) (Task, error)
	Create(ctx context.Context, in CreateInput) (Task, error)
	Update(ctx context.Context, id int64, in UpdateInput) (Task, error)
	Delete(ctx context.Context, id int64) error
	Ping(ctx context.Context) error
}

type PostgresStore struct {
	pool *pgxpool.Pool
}

func NewPostgresStore(pool *pgxpool.Pool) *PostgresStore {
	return &PostgresStore{pool: pool}
}

const columns = `id, title, status, created_at, updated_at`

func (s *PostgresStore) List(ctx context.Context) ([]Task, error) {
	rows, err := s.pool.Query(ctx, `SELECT `+columns+` FROM tasks ORDER BY id`)
	if err != nil {
		return nil, fmt.Errorf("listar tarefas: %w", err)
	}
	defer rows.Close()

	// Slice não-nil: garante que a API devolva [] e não null quando vazia.
	tasks := []Task{}
	for rows.Next() {
		var t Task
		if err := rows.Scan(&t.ID, &t.Title, &t.Status, &t.CreatedAt, &t.UpdatedAt); err != nil {
			return nil, fmt.Errorf("ler linha: %w", err)
		}
		tasks = append(tasks, t)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterar tarefas: %w", err)
	}
	return tasks, nil
}

func (s *PostgresStore) Get(ctx context.Context, id int64) (Task, error) {
	var t Task
	err := s.pool.QueryRow(ctx, `SELECT `+columns+` FROM tasks WHERE id = $1`, id).
		Scan(&t.ID, &t.Title, &t.Status, &t.CreatedAt, &t.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Task{}, ErrNotFound
	}
	if err != nil {
		return Task{}, fmt.Errorf("buscar tarefa %d: %w", id, err)
	}
	return t, nil
}

func (s *PostgresStore) Create(ctx context.Context, in CreateInput) (Task, error) {
	var t Task
	err := s.pool.QueryRow(ctx,
		`INSERT INTO tasks (title, status) VALUES ($1, $2) RETURNING `+columns,
		in.Title, in.Status,
	).Scan(&t.ID, &t.Title, &t.Status, &t.CreatedAt, &t.UpdatedAt)
	if err != nil {
		return Task{}, fmt.Errorf("criar tarefa: %w", err)
	}
	return t, nil
}

func (s *PostgresStore) Update(ctx context.Context, id int64, in UpdateInput) (Task, error) {
	var t Task
	err := s.pool.QueryRow(ctx,
		`UPDATE tasks SET title = $1, status = $2, updated_at = now() WHERE id = $3 RETURNING `+columns,
		in.Title, in.Status, id,
	).Scan(&t.ID, &t.Title, &t.Status, &t.CreatedAt, &t.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Task{}, ErrNotFound
	}
	if err != nil {
		return Task{}, fmt.Errorf("atualizar tarefa %d: %w", id, err)
	}
	return t, nil
}

func (s *PostgresStore) Delete(ctx context.Context, id int64) error {
	tag, err := s.pool.Exec(ctx, `DELETE FROM tasks WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("remover tarefa %d: %w", id, err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// Ping alimenta o /readyz. É o que o readinessProbe do Kubernetes (Fase 4)
// vai consultar para tirar o pod do Service quando o banco cair.
func (s *PostgresStore) Ping(ctx context.Context) error {
	return s.pool.Ping(ctx)
}
