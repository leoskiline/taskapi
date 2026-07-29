// Package config carrega a configuração da aplicação a partir do ambiente.
//
// Regra do laboratório: nenhuma configuração vem de arquivo commitado. Tudo é
// variável de ambiente, porque é assim que ConfigMap/Secret (Fase 4) e Helm
// values (Fase 5) vão injetar valores depois, sem rebuild da imagem.
package config

import (
	"errors"
	"fmt"
	"log/slog"
	"os"
	"strconv"
	"time"
)

type Config struct {
	Port            string
	DatabaseURL     string
	LogLevel        slog.Level
	ShutdownTimeout time.Duration
}

// Load lê o ambiente e valida. Falha rápido: se falta configuração
// obrigatória, o processo não deve subir "meio funcionando" — no Kubernetes
// um CrashLoopBackOff é um diagnóstico melhor do que um pod Running quebrado.
func Load() (Config, error) {
	cfg := Config{
		Port:        env("PORT", "8080"),
		DatabaseURL: os.Getenv("DATABASE_URL"),
	}

	if cfg.DatabaseURL == "" {
		return Config{}, errors.New("DATABASE_URL é obrigatória")
	}

	if _, err := strconv.Atoi(cfg.Port); err != nil {
		return Config{}, fmt.Errorf("PORT inválida: %q", cfg.Port)
	}

	lvl, err := parseLevel(env("LOG_LEVEL", "info"))
	if err != nil {
		return Config{}, err
	}
	cfg.LogLevel = lvl

	timeout, err := time.ParseDuration(env("SHUTDOWN_TIMEOUT", "10s"))
	if err != nil {
		return Config{}, fmt.Errorf("SHUTDOWN_TIMEOUT inválido: %w", err)
	}
	cfg.ShutdownTimeout = timeout

	return cfg, nil
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func parseLevel(s string) (slog.Level, error) {
	var lvl slog.Level
	if err := lvl.UnmarshalText([]byte(s)); err != nil {
		return 0, fmt.Errorf("LOG_LEVEL inválido: %q (use debug, info, warn ou error)", s)
	}
	return lvl, nil
}
