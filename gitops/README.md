# gitops/

Estado desejado de cada ambiente. **Este diretório é a fonte da verdade do que está implantado** — não o cluster, não o `helm upgrade` que alguém rodou terça-feira.

```
gitops/environments/
├── dev/values.yaml       ← o CI abre PR mudando image.tag aqui
└── staging/values.yaml   ← promoção manual, por PR
```

## O ciclo

1. Commit na `main` → CI roda lint, testes, smoke e publica a imagem no GHCR.
2. O job `promote` **abre um PR** trocando `image.tag` em `dev/values.yaml`.
3. O merge do PR é o deploy. O Argo CD reconcilia e aplica.

Ninguém roda `kubectl apply` nem `helm upgrade`. O runner do CI **não tem credencial do cluster** — ele só sabe escrever em git, o que reduz bastante o estrago possível se um workflow for comprometido.

## Por que estes values e não os do chart

`charts/taskapi/values-*.yaml` descreve **como a aplicação se comporta** naquele tipo de ambiente. Os arquivos daqui descrevem **o que está implantado agora**. A separação é o que permite promover uma imagem de dev para staging sem tocar no chart, e responder "qual versão está em staging?" com `git log` em vez de perguntar no Slack.

## Repositório separado

O padrão de mercado é um repositório GitOps **separado** do código, por três motivos: evita o loop CI→commit→CI, permite dar acesso de escrita ao pipeline sem dar acesso ao código-fonte, e mantém o histórico de deploy legível sem o ruído dos commits de aplicação.

Aqui está no mesmo repositório por uma razão prática: nada além de você pode criar repositório na sua conta. A mudança, quando quiser, é pequena:

1. `git mv gitops/ ../taskapi-gitops/` e publicar o novo repositório.
2. Trocar `repo_url` no `terraform/variables.tf` (o Argo já usa `sources` com `$values`, que funciona igual entre repositórios diferentes).
3. Dar ao CI um token com escrita no repositório de GitOps.

O loop, no arranjo atual, é quebrado pelo `paths-ignore: gitops/**` no gatilho de `push` do workflow.
