# ADR 0002 — Sem framework web

**Data:** 2026-07-29
**Fase:** 1
**Status:** aceita

## Contexto

O caminho usual em Go seria Gin, Echo ou Chi. Desde o Go 1.22, o `net/http` da biblioteca padrão roteia por método e aceita wildcard no path (`mux.HandleFunc("GET /tasks/{id}", ...)`), que era o principal motivo histórico para pegar um roteador de terceiros.

## Decisão

Usar só a biblioteca padrão. A única dependência direta do projeto é o driver `pgx`.

## Consequências

O objetivo deste repositório é treinar a esteira, não a aplicação. Cada dependência a mais é: mais CVE para o Trivy reportar na Fase 9, mais atualização do Dependabot para revisar, mais superfície no SBOM e mais tempo de build no CI.

O custo é escrever à mão o que um framework daria de graça — decodificação de JSON com limite de tamanho, tradução de erro de domínio para status HTTP, middleware de log. São ~60 linhas em `handler.go` e `httpx/middleware.go`, e escrevê-las é justamente o que expõe decisões que um framework esconderia (por que limitar o corpo do request, por que `DisallowUnknownFields`, por que capturar o status na resposta).

Se o projeto crescer a ponto de precisar de middleware chain complexo, o Chi é o próximo passo natural — a assinatura `func(http.Handler) http.Handler` já é compatível.
