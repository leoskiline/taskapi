# taskapi

API REST de tarefas em Go, usada como cobaia do laboratório DevOps descrito em `../PLANO-DEVOPS.md`.

A aplicação é deliberadamente pequena. A complexidade deste repositório deve crescer na **esteira** (build, deploy, observabilidade, segurança), não nas regras de negócio.

**Fase atual: 3 — CI.** Kubernetes, IaC e observabilidade chegam nas fases seguintes.

---

## Endpoints

| Método | Rota | Resposta |
|---|---|---|
| `GET` | `/tasks` | `200` lista (sempre `[]`, nunca `null`) |
| `POST` | `/tasks` | `201` + header `Location` |
| `GET` | `/tasks/{id}` | `200` / `404` |
| `PUT` | `/tasks/{id}` | `200` / `404` |
| `DELETE` | `/tasks/{id}` | `204` / `404` |
| `GET` | `/healthz` | `200` sempre que o processo estiver vivo |
| `GET` | `/readyz` | `200` se o Postgres responde, `503` se não |

Corpo de uma tarefa:

```json
{ "id": 1, "title": "estudar kubernetes", "status": "todo", "created_at": "...", "updated_at": "..." }
```

`status` ∈ `todo` | `doing` | `done`.

---

## Como rodar

Pré-requisitos: Docker e make (Go só é necessário para desenvolver). Tudo dentro do WSL2.

### Stack completa em container (recomendado)

```bash
make up       # banco + migrations + API, tudo via Compose
make ps       # estado dos serviços, incluindo health
make logs     # logs da stack
make down     # derruba (o volume de dados permanece)
make down-all # derruba e apaga o volume
```

A API sobe em `localhost:8080`. O Compose orquestra a ordem: o banco precisa passar no `pg_isready`, a migration precisa terminar com sucesso, e só então a API sobe.

### Desenvolvimento com a API fora do container

Útil para iterar rápido no código sem rebuild de imagem:

```bash
make db-up        # só o Postgres, em container
make migrate-up   # aplica as migrations
make run          # go run local, apontando para o banco em localhost
```

```bash
make help         # lista todos os alvos
```

### Testes

```bash
make test              # unitários — sem banco, rodam em ~1s
make db-up             # necessário só para o próximo comando
make test-integration  # contra o Postgres real
make lint              # golangci-lint via container, sem instalar nada
```

---

## Configuração

Só variáveis de ambiente — nenhum arquivo de config commitado. É o que permite o mesmo binário/imagem rodar em dev, staging e prod trocando apenas ConfigMap e Secret (Fase 4).

| Variável | Padrão | Obrigatória |
|---|---|---|
| `DATABASE_URL` | — | **sim** |
| `PORT` | `8080` | não |
| `LOG_LEVEL` | `info` | não (`debug`/`info`/`warn`/`error`) |
| `SHUTDOWN_TIMEOUT` | `10s` | não |

Falta de `DATABASE_URL` derruba o processo na partida, de propósito: no Kubernetes um `CrashLoopBackOff` é um diagnóstico melhor do que um pod `Running` que responde 500.

---

## A imagem

```bash
make image          # multi-stage distroless
make image-compare  # constrói as duas versões e mostra a diferença
make image-inspect  # usuário, entrypoint e healthcheck efetivos
```

Resultado medido nesta máquina:

| Imagem | Tamanho |
|---|---|
| `Dockerfile.naive` — `FROM golang`, o caminho óbvio | **1,55 GB** |
| `Dockerfile` — multi-stage + distroless | **21,3 MB** |

73x. O `Dockerfile.naive` existe só para essa comparação; não use.

Detalhes que valem entender ([ADR 0003](docs/decisions/0003-imagem-distroless-multi-stage.md)):

- **`go.mod`/`go.sum` são copiados antes do código.** Enquanto as dependências não mudarem, a camada de `go mod download` vem do cache. Copiar tudo de uma vez invalidaria o cache a cada linha alterada.
- **`CGO_ENABLED=0`** é o que permite a imagem final ser `static` — sem libc, sem linker dinâmico.
- **Roda como uid 65532**, confirmado com `docker top`. Não como root.
- **Não há shell na imagem.** `docker exec taskapi-api-1 sh` falha, e isso é intencional. Depuração se faz por log e métrica; quando for realmente necessário um shell, a saída é `kubectl debug` com container efêmero (Fase 4).
- **O `HEALTHCHECK` chama `/api -healthcheck`**, um modo do próprio binário — porque sem shell não existe `curl` para chamar.
- **A tag é o SHA do commit**, nunca `latest`. `latest` em deploy significa não saber o que está rodando nem para onde voltar.

## CI

`.github/workflows/ci.yml` roda em todo push na `main` e em todo pull request:

| Job | O que faz |
|---|---|
| `lint` | `make lint` |
| `test` | `make test` + `make test-integration` contra um service container Postgres |
| `smoke` | sobe a stack Compose inteira e exercita a API de verdade |
| `image` | build multi-arch e push para o GHCR — **só na `main`**, nunca em PR |

O ponto do job `smoke`: teste unitário não pega variável de ambiente faltando, ordem errada de dependência nem binário que não roda na imagem distroless. Ele valida o artefato, não o código.

```bash
make ci        # roda local a mesma sequência do pipeline
make ci-lint   # valida a sintaxe dos workflows (actionlint) sem dar push
```

`make ci-lint` já pagou por si: pegou um `SC2034` no loop de espera antes do primeiro push.

Decisões do pipeline ([ADR 0004](docs/decisions/0004-ci-chama-os-alvos-do-makefile.md)):

- **O CI chama os alvos do Makefile**, não comandos próprios. Falha de CI se depura rodando `make ci` local, não empurrando commits de tentativa.
- **`permissions: contents: read` no topo**, e só o job `image` pede `packages: write`. Token amplo exposto a step de terceiro é o vetor clássico de ataque em CI.
- **PR não publica imagem.** Um PR vindo de fork não deve conseguir empurrar nada para o registry.
- **Versões das ferramentas pinadas** (`golangci-lint:v2.12.2`, `migrate:v4.19.1`). Com `:latest`, o mesmo commit passa hoje e falha amanhã sem nenhum diff para olhar.
- **Sem tag `latest` no registry.** Quem quiser a ponta da `main` usa a tag `main`, que ao menos diz de onde veio.
- **Dependabot** acompanha três superfícies: módulos Go, imagens base e as próprias actions.

### Ainda pendente nesta fase

O repositório é local. Para o CI existir de fato falta criar o remote e ligar a proteção de branch:

```bash
git remote add origin git@github.com:leoskiline/taskapi.git
git push -u origin main
```

Depois, em **Settings → Branches → Add rule** na `main`: exigir PR antes do merge e exigir os checks `lint`, `test` e `smoke` verdes. Sem isso o pipeline roda mas não impede nada — e o critério de conclusão da fase é justamente ver um PR com teste quebrado ser **bloqueado**.

## Decisões que importam para as próximas fases

**Sem framework web.** Roteamento com o `net/http` do Go 1.22+ (`mux.HandleFunc("GET /tasks/{id}", ...)`). Menos dependência para atualizar e menos superfície para o Trivy reclamar na Fase 9.

**`/healthz` não toca no banco, `/readyz` toca.** Liveness responde "o processo está vivo"; readiness responde "dá para atender request". Se a liveness dependesse do Postgres, uma queda do banco faria o Kubernetes reiniciar a aplicação em loop — sem resolver nada, e ainda apagando o rastro do problema. Verificado: com o banco parado, `/readyz` devolve `503` e `/healthz` segue `200`.

**O pool de conexões é preguiçoso.** `pgxpool.New` não conecta na partida. A API sobe com o banco fora do ar e reporta isso no `/readyz`, em vez de morrer.

**Shutdown gracioso no SIGTERM.** É o sinal que o Kubernetes manda antes de matar o pod. Sem drenar as conexões, todo deploy derruba requests em andamento.

**Handler depende de interface, não de Postgres.** Por isso os testes de handler rodam em milissegundos sem Docker. Os testes de integração existem em separado porque mock de banco testa o mock — erro de SQL e `RETURNING` só aparecem contra o Postgres real.

**Log estruturado em JSON desde o dia 1.** O Loki (Fase 8) indexa por campo; log em texto livre vira regex.

**Erro interno nunca vaza para o cliente.** Detalhe vai para o log, o cliente recebe `{"error":"erro interno"}`. Há um teste que falha se uma string de conexão vazar na resposta.

**A migration é idempotente e tem `down`.** Migration sem rollback é deploy sem volta — e a Fase 7 depende de conseguir reverter.

**O `CHECK` de `status` existe mesmo com validação na aplicação.** Segunda linha de defesa: protege contra escrita que não passa pela API.

---

## Estrutura

```
cmd/api/            entrypoint: config, wiring, servidor, shutdown, modo -healthcheck
internal/config/    carga e validação do ambiente
internal/task/      domínio: modelo, validação, Store (porta + Postgres), handlers
internal/httpx/     middleware de log de request
migrations/         SQL versionado (golang-migrate)
docs/decisions/     ADRs — por que cada escolha foi feita
Dockerfile          multi-stage, imagem final distroless não-root
Dockerfile.naive    contra-exemplo, só para o exercício de comparação
docker-compose.yml  banco + migrations + API, com ordem garantida por health
```

---

## Próxima fase

**Fase 4 — Kubernetes:** cluster kind com 3 nós e os manifestos escritos à mão (Deployment, Service, ConfigMap, Secret, Ingress, StatefulSet do Postgres) antes de conhecer Helm.
