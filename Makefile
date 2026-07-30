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

# Versões pinadas: com ':latest' o mesmo commit passa hoje e falha amanhã
# porque uma imagem mudou sozinha. Em CI isso vira "quebrou e eu não mexi em
# nada" — o pior tipo de falha para depurar. Atualizar é um commit consciente.
MIGRATE_IMAGE ?= migrate/migrate:v4.19.1
LINT_IMAGE    ?= golangci/golangci-lint:v2.12.2

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

# --------------------------------------------------------------- container --

IMAGE   ?= taskapi
# Tag pelo SHA do commit, nunca 'latest': é o que permite saber exatamente qual
# código está rodando e voltar para uma versão anterior. Na Fase 3 o CI usa a
# mesma convenção.
VERSION ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo dev)

## image: constrói a imagem multi-stage distroless
.PHONY: image
image:
	DOCKER_BUILDKIT=1 docker build --build-arg VERSION=$(VERSION) -t $(IMAGE):$(VERSION) -t $(IMAGE):dev .
	@docker images $(IMAGE):$(VERSION) --format 'imagem: {{.Repository}}:{{.Tag}} — {{.Size}}'

## image-naive: constrói a versão ingênua (só para o exercício de comparação)
.PHONY: image-naive
image-naive:
	DOCKER_BUILDKIT=1 docker build -f Dockerfile.naive -t $(IMAGE):naive .

## image-compare: mostra lado a lado o tamanho da imagem ingênua e da otimizada
.PHONY: image-compare
image-compare: image image-naive
	@echo ""
	@docker images --format 'table {{.Repository}}:{{.Tag}}\t{{.Size}}' | grep -E 'REPOSITORY|$(IMAGE)'
	@echo ""
	@echo "camadas da imagem final:"
	@docker history $(IMAGE):$(VERSION) --format 'table {{.CreatedBy}}\t{{.Size}}' | head -n 8

## image-run: roda a imagem contra o banco de desenvolvimento
.PHONY: image-run
image-run:
	docker run --rm --name taskapi-api --network $(DB_NETWORK) -p 8080:8080 \
		-e DATABASE_URL="$(DATABASE_URL_DOCKER)" $(IMAGE):dev

## image-inspect: usuário, entrypoint e healthcheck efetivos da imagem
.PHONY: image-inspect
image-inspect:
	@docker inspect $(IMAGE):dev --format 'usuário:     {{.Config.User}}'
	@docker inspect $(IMAGE):dev --format 'entrypoint:  {{.Config.Entrypoint}}'
	@docker inspect $(IMAGE):dev --format 'healthcheck: {{.Config.Healthcheck.Test}}'

# ----------------------------------------------------------------- compose --

## up: sobe a stack inteira (banco + migrations + API) via Compose
.PHONY: up
up:
	# VERSION exportada para o ambiente: o Compose lê do shell, não enxerga
	# variável de Makefile. Sem isso a imagem sai marcada como "dev".
	VERSION=$(VERSION) docker compose up -d --build
	@docker compose ps

## down: derruba a stack (o volume permanece)
.PHONY: down
down:
	docker compose down

## down-all: derruba a stack e apaga o volume de dados
.PHONY: down-all
down-all:
	docker compose down -v

## logs: segue os logs da stack
.PHONY: logs
logs:
	docker compose logs -f

## ps: estado dos serviços, incluindo health
.PHONY: ps
ps:
	docker compose ps

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

## ci: roda localmente a mesma sequência do pipeline (lint + testes)
.PHONY: ci
ci: lint test
	$(MAKE) db-up
	$(MAKE) test-integration
	@echo ""
	@echo "verde local — mesma sequência que o CI executa"

## ci-lint: valida a sintaxe dos workflows do GitHub Actions sem dar push
.PHONY: ci-lint
ci-lint:
	docker run --rm -v "$(PWD)":/repo -w /repo $(ACTIONLINT_IMAGE) -color

ACTIONLINT_IMAGE ?= rhysd/actionlint:1.7.7

## clean: remove artefatos de build
.PHONY: clean
clean:
	rm -rf bin/
