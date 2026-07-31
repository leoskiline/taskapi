package task

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Teste de integração: só roda com TEST_DATABASE_URL apontando para um
// Postgres de verdade (`make test-integration`). Sem a variável ele pula, para
// que `make test` continue rápido e sem dependência externa.
//
// Por que não mockar o Postgres: mock de banco testa o mock. Erro de SQL,
// tipo de coluna e RETURNING só aparecem contra o banco real.
func newTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()

	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL não definida — pulando teste de integração")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatalf("criar pool: %v", err)
	}
	if err := pool.Ping(ctx); err != nil {
		t.Fatalf("banco inacessível em TEST_DATABASE_URL: %v", err)
	}
	t.Cleanup(pool.Close)

	aplicarMigrations(t, pool)

	// Estado limpo por teste. RESTART IDENTITY zera a sequence, senão os IDs
	// vazam de um teste para o outro e as asserções viram loteria.
	if _, err := pool.Exec(ctx, `TRUNCATE tasks RESTART IDENTITY`); err != nil {
		t.Fatalf("limpar tabela: %v", err)
	}
	return pool
}

func aplicarMigrations(t *testing.T, pool *pgxpool.Pool) {
	t.Helper()

	// As migrations vivem dentro do chart: o .Files.Glob do Helm não lê fora do
	// diretório do chart, e duplicar SQL seria pior que este caminho comprido.
	sql, err := os.ReadFile(filepath.Join("..", "..", "charts", "taskapi", "migrations", "000001_create_tasks.up.sql"))
	if err != nil {
		t.Fatalf("ler migration: %v", err)
	}
	if _, err := pool.Exec(context.Background(), string(sql)); err != nil {
		t.Fatalf("aplicar migration: %v", err)
	}
}

func TestPostgresStoreCRUD(t *testing.T) {
	store := NewPostgresStore(newTestPool(t))
	ctx := context.Background()

	criada, err := store.Create(ctx, CreateInput{Title: "subir kind", Status: StatusTodo})
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	if criada.ID == 0 {
		t.Error("ID não foi preenchido pelo RETURNING")
	}
	if criada.CreatedAt.IsZero() {
		t.Error("created_at não foi preenchido pelo default do banco")
	}

	buscada, err := store.Get(ctx, criada.ID)
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if buscada.Title != "subir kind" {
		t.Errorf("title = %q", buscada.Title)
	}

	atualizada, err := store.Update(ctx, criada.ID, UpdateInput{Title: "subir kind", Status: StatusDone})
	if err != nil {
		t.Fatalf("update: %v", err)
	}
	if atualizada.Status != StatusDone {
		t.Errorf("status = %q, esperado done", atualizada.Status)
	}
	if !atualizada.UpdatedAt.After(criada.UpdatedAt) {
		t.Error("updated_at não avançou — o SET updated_at = now() não pegou")
	}

	lista, err := store.List(ctx)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(lista) != 1 {
		t.Errorf("len(lista) = %d, esperado 1", len(lista))
	}

	if err := store.Delete(ctx, criada.ID); err != nil {
		t.Fatalf("delete: %v", err)
	}
	if _, err := store.Get(ctx, criada.ID); !errors.Is(err, ErrNotFound) {
		t.Errorf("get após delete: err = %v, esperado ErrNotFound", err)
	}
}

func TestPostgresStoreNotFound(t *testing.T) {
	store := NewPostgresStore(newTestPool(t))
	ctx := context.Background()

	if _, err := store.Get(ctx, 42); !errors.Is(err, ErrNotFound) {
		t.Errorf("get: err = %v, esperado ErrNotFound", err)
	}
	if _, err := store.Update(ctx, 42, UpdateInput{Title: "x", Status: StatusTodo}); !errors.Is(err, ErrNotFound) {
		t.Errorf("update: err = %v, esperado ErrNotFound", err)
	}
	if err := store.Delete(ctx, 42); !errors.Is(err, ErrNotFound) {
		t.Errorf("delete: err = %v, esperado ErrNotFound", err)
	}
}

func TestStatusInvalidoBarradoPeloBanco(t *testing.T) {
	pool := newTestPool(t)
	ctx := context.Background()

	// A validação de domínio já barra isso, mas o CHECK constraint é a
	// segunda linha de defesa: protege contra escrita fora da aplicação.
	_, err := pool.Exec(ctx, `INSERT INTO tasks (title, status) VALUES ($1, $2)`, "x", "pendente")
	if err == nil {
		t.Fatal("banco aceitou status inválido — o CHECK constraint sumiu")
	}
}
