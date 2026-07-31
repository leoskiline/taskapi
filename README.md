# taskapi

API REST de tarefas em Go, usada como cobaia do laboratório DevOps descrito em `../PLANO-DEVOPS.md`.

A aplicação é deliberadamente pequena. A complexidade deste repositório deve crescer na **esteira** (build, deploy, observabilidade, segurança), não nas regras de negócio.

**Fase atual: 8 — Observabilidade.** DevSecOps e nuvem chegam nas fases seguintes.

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

## Kubernetes

Os manifestos crus continuam em `k8s/` como referência do que foi escrito à mão na Fase 4. O caminho recomendado hoje é o chart.

```bash
make cluster-up            # kind com 3 nós + ingress-nginx
make helm-install ENV=dev  # instala/atualiza o release
make helm-test             # exercita /readyz, cria uma tarefa e lê de volta
make helm-status           # revisão atual + histórico
make helm-rollback         # volta uma revisão
```

O chart vive em `charts/taskapi/`, com `values-dev.yaml` (1 réplica, log debug, Postgres como subchart) e `values-prod.yaml` (3 réplicas, log warn, **banco externo** — `postgresql.enabled: false`).

Detalhes que valem entender:

- **`version` ≠ `appVersion`.** A primeira é do empacotamento, a segunda é da imagem. Corrigir um template não deveria fingir que a aplicação mudou.
- **`checksum/config` na anotação do pod.** Sem isso, mudar só um valor de ConfigMap não reinicia nada — o Deployment fica idêntico e o Helm não tem o que atualizar. Verificado: um upgrade que muda apenas `logLevel` recria o pod.
- **`taskapi.databaseURL` é um helper.** A URL do banco existe em um lugar só; o initContainer da migration e o container da aplicação não têm como divergir.
- **`--atomic` desfaz sozinho.** Um upgrade para uma tag inexistente falhou e voltou para a revisão anterior sem intervenção; a API nunca saiu do ar.
- **Sem `--atomic`, o Helm diz "deployed" mesmo com o pod em `ErrImagePull`.** "Deployed" significa "manifestos aplicados", não "aplicação saudável". É a diferença entre `helm upgrade` e `helm upgrade --atomic --wait`.
- **As migrations moram dentro do chart** (`charts/taskapi/migrations/`) porque o `.Files.Glob` não lê fora do diretório do chart. Compose, testes de integração e Makefile apontam todos para lá — uma fonte só.
- **O chart do Postgres precisou de override de imagem.** A Bitnami retirou `docker.io/bitnami/*` em 2025; sem apontar para `bitnamilegacy` o banco fica em `ImagePullBackOff` ([ADR 0005](docs/decisions/0005-postgres-como-dependencia-e-imagem-legacy.md)).

## Infraestrutura como código

Todo o ambiente — cluster, ingress-nginx e a aplicação — é criado por Terraform:

```bash
make tf-init
make tf-apply      # cluster + plataforma + app
make tf-output
make tf-destroy
```

**Reconstrução completa medida: 1m42s** entre `destroy` e `apply`, sem nenhum passo manual.

Três módulos com responsabilidades separadas: `modules/cluster` (o kind), `modules/platform` (ingress-nginx e o namespace — o que o cluster precisa ter antes de qualquer app) e `modules/app` (o release do chart). A separação é o que permite `-target=module.app` numa emergência sem arriscar o cluster, e é o desenho que a Fase 10 reaproveita trocando só o módulo de cluster por um de EKS/AKS/GKE.

### State remoto sem gastar com nuvem

```bash
make tf-backend-up   # MinIO + bucket
make tf-migrate      # init -migrate-state -force-copy
```

Backend S3 apontando para um MinIO em container, com `use_lockfile` para impedir dois `apply` simultâneos. Console em `http://localhost:9001`.

### O que estas armadilhas ensinaram

- **Provider não pode depender de recurso criado no mesmo apply.** Providers são configurados na fase de *plan*; num ambiente do zero o contexto do kubeconfig ainda não existe e o plan falha. Por isso `make tf-apply` roda em dois estágios e os providers apontam para um caminho de kubeconfig, não para atributos do cluster ([ADR 0006](docs/decisions/0006-terraform-provider-depende-de-recurso.md)).
- **`set` do provider Helm faz inferência de tipo.** `"true"` virou booleano e o apply morreu com `cannot unmarshal bool into ... nodeSelector of type string`. Em YAML (`yamlencode`) o tipo é explícito.
- **`yes | terraform init -migrate-state` destrói o rastreamento.** O comando `yes` imprime `y`, e o Terraform aceita exclusivamente a palavra `yes` — qualquer outra resposta significa "não copie o state". O resultado foi backend remoto vazio, state local zerado e um `plan` querendo recriar tudo. Salvou o `terraform.tfstate.backup` + `terraform state push`. O certo é `-force-copy`.
- **Terraform não vê drift dentro de um release do Helm.** Verificado: `kubectl label namespace` → `plan` acusa e `apply` corrige; `kubectl scale deployment` dentro do release → **`No changes`**. `helm_release` rastreia o release (chart + values), não os objetos gerados. Reconciliação objeto a objeto é trabalho do Argo CD, na Fase 7 — é literalmente a razão de ele existir.

## GitOps

O Argo CD reconcilia o cluster contra este repositório. **Ninguém roda `helm upgrade` nem `kubectl apply` para implantar.**

```
commit na main → CI (lint, testes, smoke) → imagem no GHCR
              → job promote ABRE PR mudando gitops/environments/dev/values.yaml
              → merge do PR = deploy → Argo CD reconcilia
```

UI em `http://argocd.localtest.me:8081`. Senha inicial:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

O que mudou de fronteira: o Terraform passou a cuidar **do cluster e da plataforma**, e parou na porta da aplicação. `module.app` virou condicional e sai por padrão (`manage_app_with_terraform = false`) — dois gerenciadores no mesmo release brigariam a cada `apply`, um reconciliando contra o state e o outro contra o git.

### Self-heal: o que a Fase 6 deixou em aberto

A mesma alteração, nos dois modelos:

| | `kubectl scale deployment taskapi --replicas=3` |
|---|---|
| Terraform (Fase 6) | `plan` → **`No changes`** |
| Argo CD (Fase 7) | `OutOfSync` em 5s, **revertido para 1 réplica em ~10s** |

E `kubectl delete service taskapi` → recriado em ~10s. `helm_release` rastreia o release (chart + values); o Argo reconcilia objeto a objeto. É a razão concreta de ele existir.

### Detalhes que valem entender

- **O runner do CI não tem credencial de cluster.** Ele só escreve em git. Um workflow comprometido propõe um PR — não implanta nada.
- **`paths-ignore: gitops/**` no gatilho de `push`** quebra o loop CI→commit→CI. O gatilho de `pull_request` fica **sem** filtro de propósito: a branch protection exige os checks, e um PR sem check nenhum ficaria travado para sempre.
- **`sources` múltiplas com `$values`.** O chart vem de `charts/taskapi`, os values de `gitops/environments/<env>`. É o que separa "como implantar" de "o que está implantado" — e o que torna a migração para um repositório GitOps dedicado uma troca de `repoURL`.
- **As Applications entram pelo chart `argocd-apps`, não por `kubernetes_manifest`.** Este último valida o recurso contra o schema do cluster na fase de *plan*, e o CRD `Application` só existe depois que o Argo estiver instalado — o mesmo problema de ordenação do [ADR 0006](docs/decisions/0006-terraform-provider-depende-de-recurso.md).

## Observabilidade

A aplicação expõe `/metrics`; o Prometheus coleta via `ServiceMonitor`; os alertas vêm de um `PrometheusRule` no próprio chart.

- Grafana: `http://grafana.localtest.me:8081`
- Prometheus: `kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090`

### O SLO

99% dos requests abaixo de **300ms**, taxa de erro abaixo de **5%**. Os dois números vivem em `values.yaml` (`metrics.slo`) e alimentam alerta e dashboard a partir da **mesma recording rule** — é o que evita o clássico "o alerta disparou mas o gráfico está verde".

O dashboard tem os quatro sinais de ouro (latência por percentil, tráfego, erros, saturação) mais um painel de **error budget**: com SLO de 99%, sobra 1% de orçamento; quando ele zera, o sinal é parar de lançar e estabilizar.

### Cardinalidade: o detalhe que derruba Prometheus

O label `route` guarda o **padrão** da rota (`GET /tasks/{id}`), nunca o caminho concreto (`/tasks/42`). Cada combinação de labels é uma série temporal; usar o caminho faria uma API com muitos IDs gerar milhões de séries.

Há teste que falha se isso regredir — e a verificação no cluster: **4 séries** em `http_requests_total`, uma por rota. Requests que não casam com rota nenhuma são agrupados em `route="desconhecida"`, senão um scanner varrendo URLs criaria uma série a cada 404.

### O alerta, disparado de propósito

Postgres derrubado, tráfego contra o pod:

```
t+30s  inactive   2.5%
t+40s  inactive  10.9%
t+50s  pending   19.4%
t+80s  pending   52.0%
t+90s  firing    52.0%   → Alertmanager: "taskapi com taxa de erro de 52%"
```

O `for: 2m` é o que separa alerta de ruído: sem ele, um único 500 durante um rollout acordaria alguém de madrugada.

**Um detalhe que só aparece quando as fases se encontram:** na primeira tentativa o alerta não disparou, porque o `selfHeal` do Argo CD (Fase 7) religou o Postgres em ~10 segundos e desfez a injeção de falha. Foi preciso pausar a reconciliação antes de injetar — que é exatamente o que um plantonista faz antes de mexer em produção.

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

**Fase 8 — Observabilidade:** métricas na aplicação, Prometheus e Grafana com os quatro sinais de ouro, Loki para logs, e um alerta disparado de propósito.
