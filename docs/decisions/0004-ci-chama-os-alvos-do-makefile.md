# ADR 0004 — O CI chama os alvos do Makefile, com versões pinadas

**Data:** 2026-07-29
**Fase:** 3
**Status:** aceita

## Contexto

Há duas formas de escrever um pipeline. A comum é colocar os comandos direto no YAML do workflow, usando actions especializadas (`golangci-lint-action`, `setup-postgres`, etc.). A outra é o workflow chamar os mesmos alvos que o desenvolvedor roda na própria máquina.

## Decisão

O workflow chama `make lint`, `make test`, `make test-integration`. A lógica mora no Makefile; o YAML só decide *quando* rodar e *em qual ambiente*.

As imagens das ferramentas auxiliares estão pinadas por versão: `golangci-lint:v2.12.2`, `migrate:v4.19.1`, `actionlint:1.7.7`.

## Consequências

**Sobre chamar os alvos.** O sintoma que isso evita é o "verde na minha máquina, vermelho no CI" que não se consegue reproduzir — porque local e pipeline estavam rodando comandos diferentes. Com o Makefile como contrato, depurar uma falha de CI começa por rodar `make ci` local, e não por empurrar commits de tentativa e erro para ver o que acontece.

O custo é velocidade: `make lint` puxa a imagem do golangci-lint (~1 min por execução), enquanto a `golangci-lint-action` tem cache próprio. Aceito por ora. Se o pipeline ficar lento a ponto de incomodar, a troca é trivial — mas aí local e CI podem divergir de versão, e é bom saber que se está pagando esse preço.

**Sobre pinar versões.** Com `:latest`, o mesmo commit passa hoje e falha amanhã porque uma imagem mudou sozinha. Em CI isso aparece como "quebrou e eu não mexi em nada", que é o tipo de falha mais caro de depurar: não há diff para olhar. Pinado, atualizar vira um commit consciente — e o Dependabot está configurado justamente para abrir esse commit como PR, com o CI validando antes do merge.

O mesmo raciocínio já valia para a tag da imagem da aplicação (SHA, nunca `latest`, [ADR 0003](0003-imagem-distroless-multi-stage.md)); aqui ele se estende para as ferramentas que constroem a aplicação.

**O que ainda não está pinado:** as actions do GitHub estão em tag de versão (`actions/checkout@v4`), não em SHA. Tag é mutável — quem controla a action pode mover `v4` para outro commit. O pinning por SHA é assunto da Fase 9 (cadeia de suprimentos), junto com Cosign e SBOM.
