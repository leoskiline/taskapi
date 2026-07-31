terraform {
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.9"
    }
  }
}

# O mesmo cluster que k8s/kind-config.yaml descrevia, agora declarado em código
# e com estado rastreado. A diferença prática: `terraform destroy` seguido de
# `apply` reconstrói tudo sem nenhum passo manual — que é o critério de
# conclusão desta fase.
resource "kind_cluster" "this" {
  name           = var.cluster_name
  node_image     = var.node_image
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      # Label exigido pelo ingress-nginx na receita do kind.
      kubeadm_config_patches = [
        <<-EOT
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
        EOT
      ]

      # Ponte entre a máquina e o cluster. Sem isto o Ingress existe mas é
      # inalcançável: os nós do kind são containers em uma rede própria.
      extra_port_mappings {
        container_port = 80
        host_port      = var.ingress_host_port
        protocol       = "TCP"
      }
    }

    # Um bloco `node` por worker. dynamic evita repetir o bloco à mão e
    # permite mudar a quantidade por variável.
    dynamic "node" {
      for_each = range(var.worker_count)
      content {
        role = "worker"
      }
    }
  }
}
