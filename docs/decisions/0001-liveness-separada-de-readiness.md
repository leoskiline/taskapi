# ADR 0001 — Liveness separada de readiness

**Data:** 2026-07-29
**Fase:** 1
**Status:** aceita

## Contexto

A API precisa expor endpoints de saúde que o Kubernetes vai consultar na Fase 4. A tentação é ter um único `/health` que verifica tudo, inclusive o banco.

## Decisão

Dois endpoints com semânticas diferentes:

- `/healthz` (liveness) — responde 200 enquanto o processo estiver vivo. **Não toca no banco.**
- `/readyz` (readiness) — faz `Ping` no Postgres. Devolve 503 se o banco não responde.

## Consequências

Se a liveness dependesse do banco, uma queda do Postgres faria o kubelet reiniciar todos os pods da API em loop. Reiniciar a aplicação não conserta um banco fora do ar: só apaga o rastro do incidente, zera as conexões que estavam esperando e transforma uma degradação parcial em indisponibilidade total.

Com a separação, uma queda do banco tira os pods do Service (param de receber tráfego) mas não os mata. Quando o banco volta, eles voltam sozinhos — comportamento verificado na Fase 1 parando o container do Postgres.

O custo é ter que explicar a diferença para quem lê o código, o que este ADR resolve.
