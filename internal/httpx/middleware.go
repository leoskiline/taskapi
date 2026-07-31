// Package httpx tem o encanamento HTTP que não pertence ao domínio.
package httpx

import (
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/leoskiline/taskapi/internal/metrics"
)

// statusRecorder guarda o status escrito, porque http.ResponseWriter não
// permite lê-lo de volta — e sem status não há métrica de erro na Fase 8.
type statusRecorder struct {
	http.ResponseWriter
	status int
	bytes  int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

func (r *statusRecorder) Write(b []byte) (int, error) {
	n, err := r.ResponseWriter.Write(b)
	r.bytes += n
	return n, err
}

// RequestLogger emite uma linha JSON por request. É o formato que o Loki
// (Fase 8) consegue indexar por campo, em vez de fazer regex em texto livre.
func RequestLogger(logger *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()
			rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}

			next.ServeHTTP(rec, r)

			logger.LogAttrs(r.Context(), levelFor(rec.status), "http_request",
				slog.String("method", r.Method),
				slog.String("path", r.URL.Path),
				slog.Int("status", rec.status),
				slog.Int("bytes", rec.bytes),
				slog.Duration("duration", time.Since(start)),
				slog.String("remote_addr", r.RemoteAddr),
			)
		})
	}
}

// Instrument alimenta as métricas Prometheus a cada request.
//
// Separado do RequestLogger de propósito: log e métrica respondem perguntas
// diferentes. Métrica responde "quantos e quão rápido" de forma barata e
// agregada; log responde "o que houve neste request específico". Misturar os
// dois em um middleware só faria cada mudança em um mexer no outro.
func Instrument(m *metrics.Metrics) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			m.RequestsInFlight.Inc()
			defer m.RequestsInFlight.Dec()

			start := time.Now()
			rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}

			next.ServeHTTP(rec, r)

			route := routeOf(r)
			m.RequestsTotal.WithLabelValues(r.Method, route, strconv.Itoa(rec.status)).Inc()
			m.RequestDuration.WithLabelValues(r.Method, route).Observe(time.Since(start).Seconds())
		})
	}
}

// routeOf devolve o padrão da rota que casou (ex.: "GET /tasks/{id}"), não o
// caminho concreto. É o que mantém a cardinalidade das métricas sob controle.
//
// r.Pattern é preenchido pelo ServeMux desde o Go 1.23. Quando vazio — request
// que não casou com rota nenhuma —, usa-se um valor fixo, em vez do caminho
// pedido: senão um scanner varrendo URLs aleatórias criaria uma série nova a
// cada 404.
func routeOf(r *http.Request) string {
	if r.Pattern != "" {
		return r.Pattern
	}
	return "desconhecida"
}

func levelFor(status int) slog.Level {
	switch {
	case status >= 500:
		return slog.LevelError
	case status >= 400:
		return slog.LevelWarn
	default:
		return slog.LevelInfo
	}
}
