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

  # Tudo via YAML, nada via `set`.
  #
  # Motivo concreto, aprendido quebrando: `set` usa a inferência de tipo do
  # Helm, que transforma "true" em booleano. Só que `nodeSelector` exige
  # string, e o apply morre com "cannot unmarshal bool into Go struct field
  # PodSpec.spec.template.spec.nodeSelector of type string". Em YAML o tipo é
  # explícito e a ambiguidade desaparece.
  values = [
    yamlencode({
      controller = {
        # Receita do kind: o controller escuta direto nas portas do nó, em vez
        # de depender de um LoadBalancer que não existe aqui.
        hostPort = {
          enabled = true
        }
        service = {
          type = "NodePort"
        }
        # Aspas importam: o label é a string "true", não o booleano.
        nodeSelector = {
          "ingress-ready" = "true"
        }
        # Sem o webhook de admissão: ele exige certificado gerado por Job, e
        # em laboratório só adiciona um ponto de falha na subida.
        admissionWebhooks = {
          enabled = false
        }
        # Tolera o taint do control-plane, senão o pod nunca é agendado no
        # único nó que tem o label acima.
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
