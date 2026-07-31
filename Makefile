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

# As migrations moram dentro do chart desde a Fase 5: o .Files.Glob do Helm não
# lê fora do diretório do chart. Compose, testes e Helm apontam todos para cá,
# então continua havendo uma única fonte da verdade.
MIGRATIONS_DIR ?= charts/taskapi/migrations

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
	docker run --rm --network $(DB_NETWORK) -v "$(PWD)/$(MIGRATIONS_DIR)":/migrations $(MIGRATE_IMAGE) \
		-path=/migrations -database "$(DATABASE_URL_DOCKER)" up

## migrate-down: desfaz a última migration
.PHONY: migrate-down
migrate-down:
	docker run --rm --network $(DB_NETWORK) -v "$(PWD)/$(MIGRATIONS_DIR)":/migrations $(MIGRATE_IMAGE) \
		-path=/migrations -database "$(DATABASE_URL_DOCKER)" down 1

## migrate-version: mostra a versão aplicada no banco
.PHONY: migrate-version
migrate-version:
	docker run --rm --network $(DB_NETWORK) -v "$(PWD)/$(MIGRATIONS_DIR)":/migrations $(MIGRATE_IMAGE) \
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

# -------------------------------------------------------------- kubernetes --

CLUSTER   ?= taskapi
NAMESPACE ?= taskapi

## cluster-up: cria o cluster kind (3 nós) e instala o ingress-nginx
.PHONY: cluster-up
cluster-up:
	kind create cluster --config k8s/kind-config.yaml
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
	kubectl wait --namespace ingress-nginx --for=condition=ready pod \
		--selector=app.kubernetes.io/component=controller --timeout=300s

## cluster-down: apaga o cluster inteiro
.PHONY: cluster-down
cluster-down:
	kind delete cluster --name $(CLUSTER)

## k8s-apply: aplica os manifestos (inclui o ConfigMap das migrations)
.PHONY: k8s-apply
k8s-apply:
	kubectl apply -f k8s/00-namespace.yaml
	# As migrations viram ConfigMap gerado a partir dos arquivos .sql, para não
	# manter o mesmo SQL em dois lugares. Na Fase 5 o Helm faz isso nativamente.
	kubectl create configmap taskapi-migrations -n $(NAMESPACE) \
		--from-file=$(MIGRATIONS_DIR) --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f k8s/10-config.yaml -f k8s/20-postgres.yaml -f k8s/30-api.yaml -f k8s/40-ingress.yaml
	kubectl rollout status deployment/taskapi -n $(NAMESPACE) --timeout=300s

## k8s-status: visão geral do namespace
.PHONY: k8s-status
k8s-status:
	@kubectl get pods,svc,ingress,pvc -n $(NAMESPACE) -o wide

## k8s-logs: logs de todas as réplicas da API
.PHONY: k8s-logs
k8s-logs:
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=taskapi --tail=50 -f --prefix

## k8s-smoke: exercita a API através do Ingress
.PHONY: k8s-smoke
k8s-smoke:
	@set -e; \
	H=http://taskapi.localtest.me:8081; \
	curl -fsS $$H/healthz; echo; \
	curl -fsS $$H/readyz; echo; \
	curl -fsS -X POST $$H/tasks -d '{"title":"rodando no kubernetes"}'; echo; \
	curl -fsS $$H/tasks; echo

## k8s-delete: remove a aplicação, preservando o cluster
.PHONY: k8s-delete
k8s-delete:
	kubectl delete namespace $(NAMESPACE)

# --------------------------------------------------------------------- helm --

CHART   ?= charts/taskapi
RELEASE ?= taskapi
ENV     ?= dev

## helm-deps: baixa as dependências do chart (subchart do Postgres)
.PHONY: helm-deps
helm-deps:
	helm dependency update $(CHART)

## helm-lint: valida o chart contra os values de cada ambiente
.PHONY: helm-lint
helm-lint: helm-deps
	helm lint $(CHART) -f $(CHART)/values-dev.yaml
	helm lint $(CHART) -f $(CHART)/values-prod.yaml

## helm-template: renderiza os manifestos sem tocar no cluster
.PHONY: helm-template
helm-template:
	helm template $(RELEASE) $(CHART) -f $(CHART)/values-$(ENV).yaml

## helm-install: instala ou atualiza o release (ENV=dev|prod)
.PHONY: helm-install
helm-install: helm-deps
	# --atomic: se o rollout não completar no prazo, o Helm desfaz sozinho, em
	# vez de deixar o release num estado meio aplicado.
	# --wait: só retorna quando os pods estiverem prontos de verdade.
	helm upgrade --install $(RELEASE) $(CHART) \
		--namespace $(NAMESPACE) --create-namespace \
		-f $(CHART)/values-$(ENV).yaml \
		--atomic --wait --timeout 5m

## helm-diff: mostra o que MUDARIA antes de aplicar (exige o plugin helm-diff)
.PHONY: helm-diff
helm-diff:
	helm diff upgrade $(RELEASE) $(CHART) \
		--namespace $(NAMESPACE) -f $(CHART)/values-$(ENV).yaml || \
		echo "plugin ausente: helm plugin install https://github.com/databus23/helm-diff"

## helm-test: roda os testes do chart contra o release instalado
.PHONY: helm-test
helm-test:
	helm test $(RELEASE) -n $(NAMESPACE) --logs

## helm-status: revisão atual e histórico do release
.PHONY: helm-status
helm-status:
	@helm status $(RELEASE) -n $(NAMESPACE) --show-resources | head -n 30
	@echo ""
	@helm history $(RELEASE) -n $(NAMESPACE)

## helm-rollback: volta para a revisão anterior (ou REV=n)
.PHONY: helm-rollback
helm-rollback:
	helm rollback $(RELEASE) $(REV) -n $(NAMESPACE) --wait

## helm-uninstall: remove o release
.PHONY: helm-uninstall
helm-uninstall:
	helm uninstall $(RELEASE) -n $(NAMESPACE)

# ---------------------------------------------------------------- terraform --

TF_DIR      ?= terraform
TF          ?= terraform -chdir=$(TF_DIR)
MINIO_IMAGE ?= minio/minio:RELEASE.2025-09-07T16-13-09Z
MC_IMAGE    ?= minio/mc:latest

## tf-init: inicializa o Terraform (baixa providers)
.PHONY: tf-init
tf-init:
	$(TF) init

## tf-fmt: formata os .tf
.PHONY: tf-fmt
tf-fmt:
	terraform fmt -recursive $(TF_DIR)

## tf-validate: valida sintaxe e referências, sem tocar em nada
.PHONY: tf-validate
tf-validate:
	terraform fmt -check -recursive $(TF_DIR)
	$(TF) validate

## tf-plan: mostra o que mudaria (exige o cluster já existindo)
.PHONY: tf-plan
tf-plan:
	$(TF) plan

## tf-bootstrap: cria só o cluster — primeiro estágio de um ambiente do zero
.PHONY: tf-bootstrap
tf-bootstrap:
	$(TF) apply -auto-approve -target=module.cluster

## tf-apply: cria/atualiza cluster + plataforma + aplicação
.PHONY: tf-apply
tf-apply:
	# Dois estágios, e não por capricho: os providers kubernetes e helm são
	# configurados na fase de PLAN, antes de qualquer recurso existir. Num
	# ambiente do zero, o contexto do kubeconfig ainda não existe e o plan
	# falha com "context kind-taskapi does not exist".
	#
	# O -target cria só o cluster; o apply seguinte já encontra o kubeconfig
	# escrito e planeja o resto normalmente. A partir daí, `make tf-apply` em
	# ambiente existente roda o segundo estágio sem efeito do primeiro.
	#
	# A resposta de produção para isso é separar em duas raízes com states
	# distintos (bootstrap e workloads) — ver ADR 0006.
	$(TF) apply -auto-approve -target=module.cluster
	$(TF) apply -auto-approve

## tf-destroy: derruba tudo que o Terraform criou
.PHONY: tf-destroy
tf-destroy:
	$(TF) destroy -auto-approve

## tf-output: valores expostos pela raiz
.PHONY: tf-output
tf-output:
	$(TF) output

## tf-state: lista os recursos rastreados
.PHONY: tf-state
tf-state:
	$(TF) state list

# --- backend remoto em MinIO ------------------------------------------------

## tf-backend-up: sobe o MinIO e cria o bucket do state
.PHONY: tf-backend-up
tf-backend-up:
	@docker start minio >/dev/null 2>&1 || \
	docker run -d --name minio \
		-p 9000:9000 -p 9001:9001 \
		-e MINIO_ROOT_USER=minioadmin \
		-e MINIO_ROOT_PASSWORD=minioadmin \
		-v minio-data:/data \
		$(MINIO_IMAGE) server /data --console-address ":9001" >/dev/null
	@echo "aguardando o MinIO..."
	@for i in $$(seq 1 30); do \
		curl -fsS http://localhost:9000/minio/health/live >/dev/null 2>&1 && break; \
		sleep 1; \
	done
	# --entrypoint sh é necessário: a imagem do mc já tem o próprio mc como
	# entrypoint, então passar "sh -c ..." como argumento vira subcomando do mc
	# e falha com "`sh` is not a recognized command".
	@docker run --rm --network host --entrypoint sh $(MC_IMAGE) -c \
		"mc alias set local http://localhost:9000 minioadmin minioadmin >/dev/null && \
		 mc mb --ignore-existing local/taskapi-tfstate"
	@echo "bucket pronto — console em http://localhost:9001 (minioadmin/minioadmin)"

## tf-backend-down: para o MinIO (o volume com o state permanece)
.PHONY: tf-backend-down
tf-backend-down:
	-docker rm -f minio

## tf-migrate: passa o state local para o MinIO
.PHONY: tf-migrate
tf-migrate: tf-backend-up
	cp $(TF_DIR)/backend-minio.tf.example $(TF_DIR)/backend.tf
	$(TF) init -migrate-state

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
