// Package metrics expõe a instrumentação Prometheus da aplicação.
package metrics

import (
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
)

// Metrics carrega o registry e os coletores da aplicação.
//
// Registry próprio em vez do default global: o registry padrão é uma variável
// de pacote onde qualquer dependência pode registrar o que quiser sem avisar.
// Com um registry explícito, o que aparece em /metrics é só o que este código
// decidiu expor — e os testes podem criar um registry limpo por caso.
type Metrics struct {
	Registry *prometheus.Registry

	RequestsTotal   *prometheus.CounterVec
	RequestDuration *prometheus.HistogramVec
	RequestsInFlight prometheus.Gauge
}

func New() *Metrics {
	reg := prometheus.NewRegistry()

	m := &Metrics{
		Registry: reg,

		RequestsTotal: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "http_requests_total",
				Help: "Total de requests HTTP atendidos.",
			},
			// `route` é o PADRÃO da rota (/tasks/{id}), nunca o caminho
			// concreto (/tasks/42).
			//
			// Isso não é detalhe: cada combinação distinta de labels vira uma
			// série temporal no Prometheus. Usar o caminho concreto faria uma
			// API com muitos IDs gerar milhões de séries e derrubar o
			// Prometheus — a falha clássica de cardinalidade.
			[]string{"method", "route", "status"},
		),

		RequestDuration: prometheus.NewHistogramVec(
			prometheus.HistogramOpts{
				Name: "http_request_duration_seconds",
				Help: "Latência dos requests HTTP em segundos.",
				// Buckets escolhidos em torno do SLO (300ms). Sem um bucket
				// perto do alvo, não há como calcular o cumprimento dele:
				// histograma só sabe responder sobre as fronteiras que tem.
				Buckets: []float64{0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.3, 0.5, 1, 2.5, 5},
			},
			[]string{"method", "route"},
		),

		RequestsInFlight: prometheus.NewGauge(
			prometheus.GaugeOpts{
				Name: "http_requests_in_flight",
				Help: "Requests HTTP sendo atendidos neste instante.",
			},
		),
	}

	reg.MustRegister(
		m.RequestsTotal,
		m.RequestDuration,
		m.RequestsInFlight,
		// Métricas do runtime Go e do processo: GC, goroutines, memória, file
		// descriptors. É o que responde "saturação" nos quatro sinais de ouro.
		collectors.NewGoCollector(),
		collectors.NewProcessCollector(collectors.ProcessCollectorOpts{}),
	)

	return m
}

// RegisterDBPool expõe as estatísticas do pool do pgx.
//
// Pool esgotado é uma das causas mais comuns de latência alta com CPU baixa —
// e é invisível sem esta métrica: a aplicação parece ociosa enquanto os
// requests esperam por conexão.
func (m *Metrics) RegisterDBPool(pool *pgxpool.Pool) {
	m.Registry.MustRegister(&dbPoolCollector{pool: pool})
}

type dbPoolCollector struct {
	pool *pgxpool.Pool
}

var (
	dbConnsTotal = prometheus.NewDesc(
		"db_pool_connections",
		"Conexões do pool por estado.",
		[]string{"state"}, nil,
	)
	dbConnsMax = prometheus.NewDesc(
		"db_pool_max_connections",
		"Tamanho máximo configurado do pool.",
		nil, nil,
	)
	dbAcquireWait = prometheus.NewDesc(
		"db_pool_acquire_wait_seconds_total",
		"Tempo acumulado esperando por uma conexão do pool.",
		nil, nil,
	)
)

func (c *dbPoolCollector) Describe(ch chan<- *prometheus.Desc) {
	ch <- dbConnsTotal
	ch <- dbConnsMax
	ch <- dbAcquireWait
}

func (c *dbPoolCollector) Collect(ch chan<- prometheus.Metric) {
	s := c.pool.Stat()

	ch <- prometheus.MustNewConstMetric(dbConnsTotal, prometheus.GaugeValue, float64(s.AcquiredConns()), "acquired")
	ch <- prometheus.MustNewConstMetric(dbConnsTotal, prometheus.GaugeValue, float64(s.IdleConns()), "idle")
	ch <- prometheus.MustNewConstMetric(dbConnsTotal, prometheus.GaugeValue, float64(s.TotalConns()), "total")
	ch <- prometheus.MustNewConstMetric(dbConnsMax, prometheus.GaugeValue, float64(s.MaxConns()))
	ch <- prometheus.MustNewConstMetric(dbAcquireWait, prometheus.CounterValue, s.AcquireDuration().Seconds())
}
