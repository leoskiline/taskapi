# ADR 0003 — Imagem final distroless e build multi-stage

**Data:** 2026-07-29
**Fase:** 2
**Status:** aceita

## Contexto

O caminho mais curto para containerizar uma aplicação Go é `FROM golang`, `go build`, `CMD`. Funciona na primeira tentativa e é o que a maioria dos tutoriais mostra.

## Decisão

Build em dois estágios: `golang:1.26-alpine` compila, `gcr.io/distroless/static-debian12:nonroot` executa. Só o binário atravessa a fronteira entre os estágios.

## Consequências

Medido neste repositório:

| Imagem | Tamanho |
|---|---|
| `Dockerfile.naive` (`FROM golang`) | **1,55 GB** |
| `Dockerfile` (multi-stage distroless) | **21,3 MB** |

73x menor. O que importa não é o número em si, e sim o que ele representa:

- **Pull em todo nó.** Na Fase 4 o cluster kind tem 3 nós. Cada rollout puxa a imagem em cada nó onde um pod for agendado. 1,55 GB por nó transforma um deploy de segundos em minutos.
- **Superfície de ataque.** A imagem ingênua carrega shell, gerenciador de pacotes, compilador, git e o código-fonte. Um invasor que consiga execução de comando dentro do container tem um ambiente completo à disposição. Na distroless não há nem `sh`.
- **CVEs.** Na Fase 9 o Trivy escaneia a imagem. Cada pacote Debian a mais é um CVE em potencial que alguém terá que triar — e que vai falhar o build por algo que a aplicação nem usa.
- **Root.** A ingênua roda como root; a distroless `:nonroot` roda como uid 65532. Confirmado com `docker top`. A policy do Kyverno da Fase 9 rejeita a primeira.

O custo real é a perda do `docker exec ... sh`. Não há shell para entrar no container em produção — comprovado: `docker exec taskapi-api-1 id` falha com *executable file not found*. Isso força depuração por log, métrica e `kubectl describe`, que é como se deve depurar em produção de qualquer forma. Quando for mesmo necessário abrir um shell, a saída é `kubectl debug` com um container efêmero (Fase 4), sem contaminar a imagem da aplicação.

Consequência secundária: sem shell, o `HEALTHCHECK` não pode ser `CMD curl ...`. Resolvido dando ao próprio binário um modo `-healthcheck` — 20 linhas em `main.go`, nenhuma dependência nova.
