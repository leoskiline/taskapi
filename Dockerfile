# syntax=docker/dockerfile:1

# ---------------------------------------------------------------- build ------
# O estágio de build carrega o toolchain Go inteiro (~800 MB). Nada disso vai
# para a imagem final — é justamente esse o ponto do multi-stage.
FROM golang:1.26-alpine AS build

WORKDIR /src

# go.mod/go.sum copiados primeiro, sozinhos: enquanto as dependências não
# mudarem, esta camada vem do cache e o download não se repete. Copiar o código
# antes disso invalidaria o cache a cada alteração de uma linha em .go.
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download

COPY . .

ARG VERSION=dev
# CGO_ENABLED=0 é o que permite a imagem final ser 'static': sem libc, sem
# linker dinâmico. -s -w remove tabela de símbolos e DWARF; -trimpath tira os
# caminhos absolutos de build, que são ruído e vazam a estrutura da máquina.
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux go build \
        -trimpath \
        -ldflags="-s -w -X main.version=${VERSION}" \
        -o /out/api ./cmd/api

# ---------------------------------------------------------------- final -----
# distroless static: só libs de runtime essenciais (certificados CA, tzdata,
# /etc/passwd). Sem shell, sem gerenciador de pacotes, sem coreutils — o que
# reduz drasticamente a superfície que o Trivy vai escanear na Fase 9 e o que
# um invasor teria à disposição dentro do container.
FROM gcr.io/distroless/static-debian12:nonroot

# nonroot = uid 65532. Declarado explicitamente mesmo já sendo o padrão da tag:
# na Fase 9 há uma policy do Kyverno que rejeita container rodando como root, e
# um Dockerfile explícito é mais fácil de auditar.
USER nonroot:nonroot

COPY --from=build --chown=nonroot:nonroot /out/api /api

EXPOSE 8080

# Sem shell na imagem, HEALTHCHECK precisa de forma exec e de um binário que
# exista aqui dentro — daí o modo -healthcheck do próprio api.
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD ["/api", "-healthcheck"]

ENTRYPOINT ["/api"]
