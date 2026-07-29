package task

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// fakeStore implementa Store em memória. É o motivo de o handler depender de
// uma interface: estes testes rodam em milissegundos, sem Docker e sem banco.
type fakeStore struct {
	tasks  map[int64]Task
	nextID int64
	err    error // quando setado, todo método falha — simula banco fora do ar
}

func newFakeStore() *fakeStore {
	return &fakeStore{tasks: map[int64]Task{}, nextID: 1}
}

func (f *fakeStore) List(context.Context) ([]Task, error) {
	if f.err != nil {
		return nil, f.err
	}
	out := []Task{}
	for id := int64(1); id < f.nextID; id++ {
		if t, ok := f.tasks[id]; ok {
			out = append(out, t)
		}
	}
	return out, nil
}

func (f *fakeStore) Get(_ context.Context, id int64) (Task, error) {
	if f.err != nil {
		return Task{}, f.err
	}
	t, ok := f.tasks[id]
	if !ok {
		return Task{}, ErrNotFound
	}
	return t, nil
}

func (f *fakeStore) Create(_ context.Context, in CreateInput) (Task, error) {
	if f.err != nil {
		return Task{}, f.err
	}
	t := Task{ID: f.nextID, Title: in.Title, Status: in.Status}
	f.tasks[t.ID] = t
	f.nextID++
	return t, nil
}

func (f *fakeStore) Update(_ context.Context, id int64, in UpdateInput) (Task, error) {
	if f.err != nil {
		return Task{}, f.err
	}
	t, ok := f.tasks[id]
	if !ok {
		return Task{}, ErrNotFound
	}
	t.Title, t.Status = in.Title, in.Status
	f.tasks[id] = t
	return t, nil
}

func (f *fakeStore) Delete(_ context.Context, id int64) error {
	if f.err != nil {
		return f.err
	}
	if _, ok := f.tasks[id]; !ok {
		return ErrNotFound
	}
	delete(f.tasks, id)
	return nil
}

func (f *fakeStore) Ping(context.Context) error { return f.err }

func newTestServer(store Store) http.Handler {
	logger := slog.New(slog.NewJSONHandler(io.Discard, nil))
	mux := http.NewServeMux()
	NewHandler(store, logger).Register(mux)
	return mux
}

func do(t *testing.T, h http.Handler, method, path, body string) *httptest.ResponseRecorder {
	t.Helper()
	var r *http.Request
	if body == "" {
		r = httptest.NewRequest(method, path, nil)
	} else {
		r = httptest.NewRequest(method, path, strings.NewReader(body))
		r.Header.Set("Content-Type", "application/json")
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}

func TestCreateTask(t *testing.T) {
	h := newTestServer(newFakeStore())

	w := do(t, h, http.MethodPost, "/tasks", `{"title":"estudar kubernetes"}`)

	if w.Code != http.StatusCreated {
		t.Fatalf("status = %d, esperado %d (corpo: %s)", w.Code, http.StatusCreated, w.Body)
	}
	if got := w.Header().Get("Location"); got != "/tasks/1" {
		t.Errorf("Location = %q, esperado /tasks/1", got)
	}

	var got Task
	if err := json.NewDecoder(w.Body).Decode(&got); err != nil {
		t.Fatalf("decodificar resposta: %v", err)
	}
	if got.Title != "estudar kubernetes" {
		t.Errorf("title = %q", got.Title)
	}
	// Status ausente na entrada deve virar "todo" pela regra de domínio.
	if got.Status != StatusTodo {
		t.Errorf("status = %q, esperado %q", got.Status, StatusTodo)
	}
}

func TestCreateTaskInvalido(t *testing.T) {
	h := newTestServer(newFakeStore())

	casos := map[string]string{
		"titulo vazio":     `{"title":"   "}`,
		"status invalido":  `{"title":"x","status":"pendente"}`,
		"json quebrado":    `{"title":`,
		"campo desconheci": `{"title":"x","prioridade":3}`,
	}

	for nome, corpo := range casos {
		t.Run(nome, func(t *testing.T) {
			w := do(t, h, http.MethodPost, "/tasks", corpo)
			if w.Code != http.StatusBadRequest {
				t.Errorf("status = %d, esperado 400 (corpo: %s)", w.Code, w.Body)
			}
		})
	}
}

func TestGetTaskInexistente(t *testing.T) {
	h := newTestServer(newFakeStore())

	w := do(t, h, http.MethodGet, "/tasks/999", "")

	if w.Code != http.StatusNotFound {
		t.Fatalf("status = %d, esperado 404", w.Code)
	}
}

func TestIDInvalido(t *testing.T) {
	h := newTestServer(newFakeStore())

	for _, path := range []string{"/tasks/abc", "/tasks/0", "/tasks/-1"} {
		w := do(t, h, http.MethodGet, path, "")
		if w.Code != http.StatusBadRequest {
			t.Errorf("%s: status = %d, esperado 400", path, w.Code)
		}
	}
}

func TestListaVaziaRetornaArray(t *testing.T) {
	h := newTestServer(newFakeStore())

	w := do(t, h, http.MethodGet, "/tasks", "")

	// Detalhe que quebra cliente na vida real: null em vez de [].
	if body := strings.TrimSpace(w.Body.String()); body != "[]" {
		t.Errorf("corpo = %q, esperado []", body)
	}
}

func TestCicloCompleto(t *testing.T) {
	h := newTestServer(newFakeStore())

	if w := do(t, h, http.MethodPost, "/tasks", `{"title":"escrever Dockerfile"}`); w.Code != http.StatusCreated {
		t.Fatalf("create: status = %d", w.Code)
	}
	if w := do(t, h, http.MethodPut, "/tasks/1", `{"title":"escrever Dockerfile","status":"done"}`); w.Code != http.StatusOK {
		t.Fatalf("update: status = %d", w.Code)
	}

	w := do(t, h, http.MethodGet, "/tasks/1", "")
	var got Task
	if err := json.NewDecoder(w.Body).Decode(&got); err != nil {
		t.Fatalf("decodificar: %v", err)
	}
	if got.Status != StatusDone {
		t.Errorf("status = %q, esperado done", got.Status)
	}

	if w := do(t, h, http.MethodDelete, "/tasks/1", ""); w.Code != http.StatusNoContent {
		t.Fatalf("delete: status = %d", w.Code)
	}
	if w := do(t, h, http.MethodGet, "/tasks/1", ""); w.Code != http.StatusNotFound {
		t.Fatalf("get apos delete: status = %d, esperado 404", w.Code)
	}
}

func TestErroInternoNaoVazaDetalhe(t *testing.T) {
	store := newFakeStore()
	store.err = errDeBanco{}
	h := newTestServer(store)

	w := do(t, h, http.MethodGet, "/tasks", "")

	if w.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, esperado 500", w.Code)
	}
	if strings.Contains(w.Body.String(), "connection refused") {
		t.Errorf("resposta vazou detalhe interno: %s", w.Body)
	}
}

type errDeBanco struct{}

func (errDeBanco) Error() string { return "dial tcp 127.0.0.1:5432: connection refused" }
