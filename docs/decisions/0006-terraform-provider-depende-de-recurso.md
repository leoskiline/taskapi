# ADR 0006 — Apply em dois estágios, e por que providers não podem depender de recursos

**Data:** 2026-07-31
**Fase:** 6
**Status:** aceita

## Contexto

A raiz do Terraform cria três coisas em ordem: o cluster kind, a plataforma (ingress-nginx, namespace) e a aplicação (o chart da Fase 5). As duas últimas usam os providers `kubernetes` e `helm`, que precisam saber como falar com um apiserver que **o próprio Terraform acabou de criar**.

Na primeira tentativa, com o cluster ainda inexistente:

```
Error: Provider configuration: cannot load Kubernetes client config
  with provider["registry.terraform.io/hashicorp/kubernetes"]
context "kind-taskapi" does not exist
```

## Por que isso acontece

Providers são configurados na fase de **plan**, antes de qualquer recurso ser criado. Não existe "planejar o provider depois que o cluster subir": o Terraform precisa de um provider funcional para saber o que planejar.

Isso vale mesmo que a configuração do provider aponte para atributos do recurso do cluster (`host = kind_cluster.this.endpoint`). Nesse caso, o plan inicial até funciona — os valores ficam "known after apply" —, mas o `destroy` e o `refresh` passam a falhar, porque aí o Terraform precisa configurar o provider para verificar um recurso que talvez já não exista. É uma armadilha que aparece semanas depois, no pior momento.

## Decisão

1. Os providers apontam para um **caminho de kubeconfig** (`~/.kube/config` + contexto), nunca para atributos do recurso. Isso elimina o acoplamento e mantém `destroy`/`refresh` saudáveis.
2. `depends_on` explícito entre os módulos, já que a dependência implícita deixou de existir por causa da escolha acima.
3. `make tf-apply` roda em **dois estágios**: `apply -target=module.cluster` e depois o apply completo.

## Consequências

O `-target` tem má fama merecida — usá-lo rotineiramente esconde dependências mal declaradas. Aqui o uso é o legítimo: bootstrap de um ambiente do zero, documentado e automatizado no Makefile, não um contorno manual para um plan que ninguém entende.

Em ambiente já existente, `make tf-apply` roda o primeiro estágio como no-op e segue direto. O custo é um plan a mais.

**A resposta de produção é outra:** separar em duas raízes com states independentes — uma que cria o cluster, outra que instala workloads e lê o endpoint via `terraform_remote_state` ou data source. Isso resolve o problema por desenho, em vez de por ordem de comando, e ainda permite que times diferentes apliquem cada uma. Não foi feito aqui porque duplicaria o state bem no momento em que a fase migra o state para o MinIO; fica registrado como o próximo passo natural se este laboratório crescer.
