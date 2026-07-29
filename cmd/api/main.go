// Command api sobe o servidor HTTP da taskapi.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/leoskiline/taskapi/internal/config"
	"github.com/leoskiline/taskapi/internal/httpx"
	"github.com/leoskiline/taskapi/internal/task"
)

func main() {
	if err := run(); err != nil {
		slog.Error("encerrando com erro", "err", err)
		os.Exit(1)
	}
}

func run() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: cfg.LogLevel}))
	slog.SetDefault(logger)

	// NotifyContext cancela o ctx no SIGTERM — que é exatamente o sinal que o
	// Kubernetes manda antes de matar o pod. Sem isso, todo deploy derruba
	// requests em andamento.
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// pgxpool.New não conecta de imediato: valida a string e cria o pool
	// preguiçosamente. É proposital — a API sobe mesmo com o banco fora do ar
	// e reporta isso no /readyz, em vez de entrar em CrashLoopBackOff.
	pool, err := pgxpool.New(ctx, cfg.DatabaseURL)
	if err != nil {
		return fmt.Errorf("configurar pool do banco: %w", err)
	}
	defer pool.Close()

	store := task.NewPostgresStore(pool)

	mux := http.NewServeMux()
	task.NewHandler(store, logger).Register(mux)
	mux.HandleFunc("GET /healthz", healthz)
	mux.HandleFunc("GET /readyz", readyz(store))

	srv := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           httpx.RequestLogger(logger)(mux),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	serverErr := make(chan error, 1)
	go func() {
		logger.Info("servidor iniciado", "addr", srv.Addr, "log_level", cfg.LogLevel.String())
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			serverErr <- err
		}
	}()

	select {
	case err := <-serverErr:
		return fmt.Errorf("servidor HTTP: %w", err)
	case <-ctx.Done():
		logger.Info("sinal de término recebido, drenando conexões")
	}

	// Shutdown com contexto novo: o ctx original já está cancelado.
	shutdownCtx, cancel := context.WithTimeout(context.Background(), cfg.ShutdownTimeout)
	defer cancel()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		return fmt.Errorf("shutdown: %w", err)
	}
	logger.Info("encerrado com sucesso")
	return nil
}

// healthz = liveness: o processo está vivo? Não toca no banco de propósito.
// Se dependesse do Postgres, uma queda do banco faria o Kubernetes reiniciar
// a aplicação em loop sem motivo.
func healthz(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"status":"ok"}`))
}

// readyz = readiness: dá para atender request? Aqui sim o banco importa —
// sem ele a API não serve para nada, e o pod deve sair do Service.
func readyz(store task.Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()

		w.Header().Set("Content-Type", "application/json")
		if err := store.Ping(ctx); err != nil {
			slog.WarnContext(ctx, "readiness falhou", "err", err)
			w.WriteHeader(http.StatusServiceUnavailable)
			_, _ = w.Write([]byte(`{"status":"degraded","dependency":"postgres"}`))
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"ready"}`))
	}
}
