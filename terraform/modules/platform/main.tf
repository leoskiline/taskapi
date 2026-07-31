terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
  }
}

# "Plataforma" = o que o cluster precisa ter antes de qualquer aplicação subir.
# Separar isto da aplicação importa: o time que cuida da plataforma e o que
# cuida do produto mudam em ritmos diferentes, e um `terraform apply` da app
# não deveria poder derrubar o ingress controller de todo mundo.

resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = var.ingress_nginx_version

  namespace        = "ingress-nginx"
  create_namespace = true

  # Espera os pods ficarem prontos antes de dar o apply por concluído — mesmo
  # motivo do --wait da Fase 5: "aplicado" não é "funcionando".
  wait    = true
  timeout = 600

  # A receita do kind: o controller usa hostPort e roda no nó rotulado
  # ingress-ready, em vez de depender de um LoadBalancer que não existe aqui.
  set = [
    {
      name  = "controller.hostPort.enabled"
      value = "true"
    },
    {
      name  = "controller.service.type"
      value = "NodePort"
    },
    {
      name  = "controller.nodeSelector.ingress-ready"
      value = "true"
    },
    {
      name  = "controller.admissionWebhooks.enabled"
      value = "false"
    },
  ]

  # Tolera o taint do control-plane, senão o pod nunca é agendado no nó certo.
  values = [
    yamlencode({
      controller = {
        tolerations = [
          {
            key      = "node-role.kubernetes.io/control-plane"
            operator = "Equal"
            effect   = "NoSchedule"
          }
        ]
      }
    })
  ]
}

resource "kubernetes_namespace" "app" {
  metadata {
    name = var.app_namespace
    labels = {
      "app.kubernetes.io/part-of" = "taskapi"
      "managed-by"                = "terraform"
    }
  }
}
