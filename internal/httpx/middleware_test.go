package httpx

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/prometheus/client_golang/prometheus/testutil"

	"github.com/leoskiline/taskapi/internal/metrics"
)

func TestInstrumentUsaPadraoDaRotaNaoOCaminho(t *testing.T) {
	m := metrics.New()

	mux := http.NewServeMux()
	mux.HandleFunc("GET /tasks/{id}", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	h := Instrument(m)(mux)

	// Três IDs diferentes: se o label usasse o caminho, viriam três séries.
	for _, id := range []string{"1", "2", "999"} {
		r := httptest.NewRequest(http.MethodGet, "/tasks/"+id, nil)
		h.ServeHTTP(httptest.NewRecorder(), r)
	}

	if got := testutil.CollectAndCount(m.RequestsTotal); got != 1 {
		t.Errorf("séries em http_requests_total = %d, esperado 1 — cardinalidade escapou", got)
	}
	if got := testutil.ToFloat64(m.RequestsTotal.WithLabelValues("GET", "GET /tasks/{id}", "200")); got != 3 {
		t.Errorf("contador = %v, esperado 3", got)
	}
}

func TestInstrumentNaoCriaSeriePorCaminhoDesconhecido(t *testing.T) {
	m := metrics.New()

	mux := http.NewServeMux()
	mux.HandleFunc("GET /tasks", func(w http.ResponseWriter, _ *http.Request) {})
	h := Instrument(m)(mux)

	// Um scanner varrendo URLs aleatórias não pode inflar as séries.
	for _, p := range []string{"/admin", "/wp-login.php", "/.env"} {
		r := httptest.NewRequest(http.MethodGet, p, nil)
		h.ServeHTTP(httptest.NewRecorder(), r)
	}

	if got := testutil.ToFloat64(m.RequestsTotal.WithLabelValues("GET", "desconhecida", "404")); got != 3 {
		t.Errorf("rotas desconhecidas agrupadas = %v, esperado 3", got)
	}
}

func TestInstrumentRegistraStatusDeErro(t *testing.T) {
	m := metrics.New()

	mux := http.NewServeMux()
	mux.HandleFunc("GET /boom", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	})
	h := Instrument(m)(mux)

	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/boom", nil))

	if got := testutil.ToFloat64(m.RequestsTotal.WithLabelValues("GET", "GET /boom", "500")); got != 1 {
		t.Errorf("contador de 500 = %v, esperado 1", got)
	}
}

func TestMetricasExpostasTemOsNomesEsperados(t *testing.T) {
	m := metrics.New()

	mux := http.NewServeMux()
	mux.HandleFunc("GET /tasks", func(w http.ResponseWriter, _ *http.Request) {})
	Instrument(m)(mux).ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/tasks", nil))

	// Os nomes fazem parte do contrato: o alerta e o dashboard dependem deles.
	// Renomear sem atualizar as regras quebra em silêncio.
	esperados := []string{
		"http_requests_total",
		"http_request_duration_seconds",
		"http_requests_in_flight",
	}

	got, err := m.Registry.Gather()
	if err != nil {
		t.Fatalf("gather: %v", err)
	}

	nomes := make([]string, 0, len(got))
	for _, mf := range got {
		nomes = append(nomes, mf.GetName())
	}
	todos := strings.Join(nomes, " ")

	for _, e := range esperados {
		if !strings.Contains(todos, e) {
			t.Errorf("métrica %q não foi exposta", e)
		}
	}
}
