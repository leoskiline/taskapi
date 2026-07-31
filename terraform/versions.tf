terraform {
  required_version = ">= 1.9"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.9"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }

  # O backend começa local, de propósito. A migração para o S3 do MinIO é feita
  # depois com `terraform init -migrate-state`, para que se veja o antes e o
  # depois — ver terraform/backend-minio.tf.example e o alvo make tf-backend-up.
}

provider "kind" {}

provider "docker" {}

# Os providers do Kubernetes e do Helm apontam para um CAMINHO de kubeconfig,
# não para atributos do recurso do cluster.
#
# Isso é deliberado: configurar um provider a partir de atributos de um recurso
# criado no mesmo apply funciona na primeira vez e quebra no `destroy` e no
# `refresh`, porque o Terraform precisa configurar o provider antes de saber se
# o recurso ainda existe. Com um caminho fixo, o acoplamento some — e o kind já
# escreve o contexto neste arquivo ao criar o cluster.
provider "kubernetes" {
  config_path    = pathexpand(var.kubeconfig_path)
  config_context = "kind-${var.cluster_name}"
}

provider "helm" {
  kubernetes = {
    config_path    = pathexpand(var.kubeconfig_path)
    config_context = "kind-${var.cluster_name}"
  }
}
