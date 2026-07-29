# taskapi

API REST de tarefas em Go, usada como cobaia do laboratório DevOps descrito em `../PLANO-DEVOPS.md`.

A aplicação é deliberadamente pequena. A complexidade deste repositório deve crescer na **esteira** (build, deploy, observabilidade, segurança), não nas regras de negócio.

**Fase atual: 1 — aplicação + Git.** Docker, CI, Kubernetes e o resto chegam nas fases seguintes.

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

Pré-requisitos: Go 1.26+, Docker, make. Tudo dentro do WSL2.

```bash
make db-up        # sobe o Postgres em container e espera ficar pronto
make migrate-up   # aplica as migrations (golang-migrate via container)
make run          # sobe a API em localhost:8080
```

Ou em um comando só: `make dev`.

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
cmd/api/          entrypoint: config, wiring, servidor, shutdown
internal/config/  carga e validação do ambiente
internal/task/    domínio: modelo, validação, Store (porta + Postgres), handlers
internal/httpx/   middleware de log de request
migrations/       SQL versionado (golang-migrate)
docs/decisions/   ADRs — por que cada escolha foi feita
```

---

## Próxima fase

**Fase 2 — containerização:** `Dockerfile` multi-stage com imagem final distroless, usuário não-root e `docker-compose.yml` substituindo os alvos `db-up`/`migrate-up` deste Makefile.
