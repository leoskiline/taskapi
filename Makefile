# Makefile como interface única do projeto. Regra: todo comando que você
# rodaria à mão vira um alvo aqui — é isso que o CI (Fase 3) vai chamar, para
# que "quebrou no CI" seja reproduzível localmente com o mesmo comando.

SHELL := /bin/bash

# --- Banco de desenvolvimento (Fase 1: docker run cru; Fase 2 vira Compose) ---
DB_CONTAINER ?= taskapi-db
DB_NETWORK   ?= taskapi-net
DB_IMAGE     ?= postgres:17-alpine
DB_USER      ?= taskapi
DB_PASSWORD  ?= taskapi
DB_NAME      ?= taskapi
DB_PORT      ?= 5432

# Credencial fraca de propósito: é banco descartável de dev. A partir da
# Fase 4 isso vira Secret, e na Fase 9, External Secrets.
DATABASE_URL ?= postgres://$(DB_USER):$(DB_PASSWORD)@localhost:$(DB_PORT)/$(DB_NAME)?sslmode=disable

# URL vista de dentro da rede do Docker: o container resolve o banco pelo NOME
# do container, não por localhost. Entender essa diferença evita metade dos
# problemas de rede da Fase 2.
DATABASE_URL_DOCKER := postgres://$(DB_USER):$(DB_PASSWORD)@$(DB_CONTAINER):5432/$(DB_NAME)?sslmode=disable

MIGRATE_IMAGE ?= migrate/migrate:latest
LINT_IMAGE    ?= golangci/golangci-lint:latest

.DEFAULT_GOAL := help

## help: lista os alvos disponíveis
.PHONY: help
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## //' | awk -F': ' '{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------- aplicação --

## run: sobe a API local apontando para o banco em container
.PHONY: run
run:
	DATABASE_URL="$(DATABASE_URL)" go run ./cmd/api

## build: compila o binário em bin/api
.PHONY: build
build:
	CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o bin/api ./cmd/api
	@ls -lh bin/api

## test: testes unitários (sem banco, rápidos)
.PHONY: test
test:
	go test -race -cover ./...

## test-integration: testes contra o Postgres real (precisa de make db-up)
.PHONY: test-integration
test-integration:
	TEST_DATABASE_URL="$(DATABASE_URL)" go test -race -count=1 ./internal/task/ -run 'Postgres|Banco' -v

## lint: golangci-lint via container (sem instalar nada)
.PHONY: lint
lint:
	docker run --rm -v "$(PWD)":/app -w /app $(LINT_IMAGE) golangci-lint run

## fmt: formata e organiza imports
.PHONY: fmt
fmt:
	go fmt ./...
	go vet ./...

## tidy: sincroniza go.mod/go.sum
.PHONY: tidy
tidy:
	go mod tidy

# --------------------------------------------------------------------- banco --

## db-up: sobe o Postgres de desenvolvimento e espera ficar pronto
.PHONY: db-up
db-up:
	@docker network inspect $(DB_NETWORK) >/dev/null 2>&1 || docker network create $(DB_NETWORK)
	@docker start $(DB_CONTAINER) >/dev/null 2>&1 || \
	docker run -d --name $(DB_CONTAINER) --network $(DB_NETWORK) \
		-e POSTGRES_USER=$(DB_USER) \
		-e POSTGRES_PASSWORD=$(DB_PASSWORD) \
		-e POSTGRES_DB=$(DB_NAME) \
		-p $(DB_PORT):5432 \
		-v taskapi-pgdata:/var/lib/postgresql/data \
		$(DB_IMAGE) >/dev/null
	@echo "aguardando o Postgres aceitar conexões..."
	@for i in $$(seq 1 30); do \
		docker exec $(DB_CONTAINER) pg_isready -U $(DB_USER) -d $(DB_NAME) >/dev/null 2>&1 && \
		{ echo "banco pronto em localhost:$(DB_PORT)"; exit 0; }; \
		sleep 1; \
	done; \
	echo "timeout esperando o banco"; exit 1

## db-down: para e remove o container do banco (o volume permanece)
.PHONY: db-down
db-down:
	-docker rm -f $(DB_CONTAINER)

## db-nuke: remove container E volume — apaga todos os dados
.PHONY: db-nuke
db-nuke: db-down
	-docker volume rm taskapi-pgdata

## db-logs: acompanha os logs do banco
.PHONY: db-logs
db-logs:
	docker logs -f $(DB_CONTAINER)

## psql: abre um shell SQL no banco de desenvolvimento
.PHONY: psql
psql:
	docker exec -it $(DB_CONTAINER) psql -U $(DB_USER) -d $(DB_NAME)

# ---------------------------------------------------------------- migrations --

## migrate-up: aplica as migrations pendentes
.PHONY: migrate-up
migrate-up:
	docker run --rm --network $(DB_NETWORK) -v "$(PWD)/migrations":/migrations $(MIGRATE_IMAGE) \
		-path=/migrations -database "$(DATABASE_URL_DOCKER)" up

## migrate-down: desfaz a última migration
.PHONY: migrate-down
migrate-down:
	docker run --rm --network $(DB_NETWORK) -v "$(PWD)/migrations":/migrations $(MIGRATE_IMAGE) \
		-path=/migrations -database "$(DATABASE_URL_DOCKER)" down 1

## migrate-version: mostra a versão aplicada no banco
.PHONY: migrate-version
migrate-version:
	docker run --rm --network $(DB_NETWORK) -v "$(PWD)/migrations":/migrations $(MIGRATE_IMAGE) \
		-path=/migrations -database "$(DATABASE_URL_DOCKER)" version

# ------------------------------------------------------------------ atalhos --

## dev: banco + migrations + API, em um comando
.PHONY: dev
dev: db-up migrate-up run

## smoke: exercita a API rodando (precisa de make run em outro terminal)
.PHONY: smoke
smoke:
	@set -e; \
	curl -fsS localhost:8080/healthz; echo; \
	curl -fsS localhost:8080/readyz; echo; \
	curl -fsS -X POST localhost:8080/tasks -d '{"title":"tarefa de fumaça"}'; echo; \
	curl -fsS localhost:8080/tasks; echo

## clean: remove artefatos de build
.PHONY: clean
clean:
	rm -rf bin/
