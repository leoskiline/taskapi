terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}

# Argo CD entra como parte da plataforma, instalado por Terraform. A partir
# daqui a fronteira muda: o Terraform cuida do cluster e do que roda nele por
# baixo; QUEM implanta a aplicação passa a ser o Argo, lendo o git.
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_version

  namespace        = "argocd"
  create_namespace = true

  wait    = true
  timeout = 900

  values = [
    yamlencode({
      # Laboratório: um nó, sem alta disponibilidade, sem TLS interno.
      redis-ha = { enabled = false }
      controller = {
        replicas = 1
      }
      server = {
        replicas = 1
        # --insecure: o servidor fala HTTP puro e quem termina TLS é o
        # Ingress. Sem isto o nginx tentaria HTTP contra uma porta HTTPS e
        # devolveria 502.
        extraArgs = ["--insecure"]
        ingress = {
          enabled          = true
          ingressClassName = "nginx"
          hostname         = var.argocd_host
          path             = "/"
          pathType         = "Prefix"
        }
      }
      repoServer     = { replicas = 1 }
      applicationSet = { replicas = 1 }
      dex            = { enabled = false }
      notifications  = { enabled = false }

      configs = {
        params = {
          "server.insecure" = true
        }
      }
    })
  ]
}

# As Applications do Argo entram por um chart próprio, e não por
# kubernetes_manifest.
#
# Motivo: kubernetes_manifest valida o recurso contra o schema do cluster na
# fase de PLAN — e o CRD Application só passa a existir depois que o Argo for
# instalado. É o mesmo problema de ordenação do ADR 0006, com outra roupa.
resource "helm_release" "apps" {
  name       = "argocd-apps"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_version

  namespace = helm_release.argocd.namespace

  values = [
    yamlencode({
      applications = {
        taskapi = {
          namespace = helm_release.argocd.namespace
          project   = "default"

          # Duas fontes: o chart vem de charts/taskapi, e os values vêm de
          # gitops/environments/<env>. A referência $values é o que permite
          # separar "como implantar" de "o que está implantado" — e é o que
          # torna a migração para um repositório GitOps dedicado uma troca de
          # repoURL, nada mais.
          sources = [
            {
              repoURL        = var.repo_url
              targetRevision = var.target_revision
              ref            = "values"
            },
            {
              repoURL        = var.repo_url
              targetRevision = var.target_revision
              path           = "charts/taskapi"
              helm = {
                valueFiles = [
                  "$values/gitops/environments/${var.environment}/values.yaml"
                ]
              }
            },
          ]

          destination = {
            server    = "https://kubernetes.default.svc"
            namespace = var.app_namespace
          }

          syncPolicy = {
            automated = {
              # prune: apaga o que sai do git.
              prune = true
              # selfHeal: desfaz mudança feita direto no cluster. É a resposta
              # ao que a Fase 6 mostrou — o Terraform não via `kubectl scale`
              # dentro de um release; o Argo vê e reverte.
              selfHeal = true
            }
            syncOptions = [
              "CreateNamespace=false",
              "ApplyOutOfSyncOnly=true",
            ]
            retry = {
              limit = 3
              backoff = {
                duration    = "10s"
                factor      = 2
                maxDuration = "2m"
              }
            }
          }
        }
      }
    })
  ]
}
