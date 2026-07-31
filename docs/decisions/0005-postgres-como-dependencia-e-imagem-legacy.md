# ADR 0005 — Postgres como dependência do chart, e o desvio para `bitnamilegacy`

**Data:** 2026-07-31
**Fase:** 5
**Status:** aceita, com ressalva

## Contexto

Na Fase 4 o Postgres era um `StatefulSet` escrito e mantido por nós. Manter banco de dados é trabalho de especialista: backup, failover, upgrade de major, tuning de `shared_buffers`. Um chart comunitário maduro já resolveu isso.

## Decisão

O Postgres vira dependência declarada em `Chart.yaml` (`bitnamicharts/postgresql`, versão fixada em `16.7.27`), com `condition: postgresql.enabled`. Em `values-prod.yaml` a condição é `false` e a aplicação aponta para um banco externo.

## O problema que apareceu ao instalar

O chart 16.7.27 referencia `docker.io/bitnami/postgresql:17.6.0-debian-12-r4`. Essa imagem **não existe mais**:

```
Error response from daemon: failed to resolve reference
"docker.io/bitnami/postgresql:17.6.0-debian-12-r4": not found
```

Em 2025 a Bitnami reorganizou seu catálogo: as imagens gratuitas foram movidas para o repositório `bitnamilegacy`, e `docker.io/bitnami/*` passou a servir o catálogo comercial. O chart publicado ficou apontando para um caminho morto — sem que nada no chart mudasse.

Correção aplicada em `values.yaml`:

```yaml
postgresql:
  image:
    registry: docker.io
    repository: bitnamilegacy/postgresql
    tag: 17.6.0-debian-12-r4
```

## Consequências

Três lições que valem mais que a configuração em si:

1. **Chart de terceiro é dependência com prazo de validade.** O YAML continuou válido; o mundo em volta é que mudou. Sem versão fixada e sem `helm test`, isso vira um `ImagePullBackOff` na madrugada de um deploy.
2. **`values` é a válvula de escape.** Não foi preciso forkar o chart nem esperar upstream corrigir — um override de três linhas resolveu. É exatamente para isso que a indireção existe.
3. **`bitnamilegacy` está congelado.** Não recebe correção de CVE. Para laboratório é aceitável; a Fase 9, quando o Trivy escanear as imagens, vai cobrar essa conta. As saídas reais são: assinar o Bitnami Secure Images, migrar para um operador (CloudNativePG), ou voltar a manter o StatefulSet próprio com a imagem oficial `postgres:17-alpine` — que, ironicamente, é o que a Fase 4 já fazia.

A ressalva do status é essa: a decisão de usar o chart está certa, a imagem escolhida é uma dívida conhecida e datada.

## Nota sobre o diretório `migrations/`

Migrar para Helm obrigou a mover `migrations/` para dentro de `charts/taskapi/`, porque `.Files.Glob` não enxerga fora do diretório do chart. As três outras consumidoras (Compose, testes de integração e os alvos do Makefile) passaram a apontar para lá. A alternativa era duplicar o SQL, o que é pior: duas verdades divergem em silêncio. Restrição de empacotamento moldando o layout do repositório é normal — o importante foi não resolver com cópia.
