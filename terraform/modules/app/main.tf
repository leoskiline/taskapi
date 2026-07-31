terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

# Data source: consulta o registry SEM criar nada. Serve para descobrir o
# digest da tag antes do deploy.
data "docker_registry_image" "app" {
  name = "${var.image_repository}:${var.image_tag}"
}

resource "helm_release" "app" {
  name      = var.release_name
  chart     = var.chart_path
  namespace = var.namespace

  # Mesma proteção da Fase 5, agora em código: se o rollout não completar,
  # o Helm desfaz em vez de deixar o release meio aplicado.
  atomic  = true
  wait    = true
  timeout = 300

  values = [file("${var.chart_path}/values-${var.environment}.yaml")]

  set = [
    {
      name  = "image.repository"
      value = var.image_repository
    },
    {
      name  = "image.tag"
      value = var.image_tag
    },
  ]

  lifecycle {
    # A lição da Fase 5 virando guarda-corpo: lá, uma tag inexistente só deu
    # as caras como ImagePullBackOff depois do deploy começar. Aqui o apply
    # falha ANTES de tocar no cluster, com uma mensagem que diz o que houve.
    precondition {
      condition     = data.docker_registry_image.app.sha256_digest != ""
      error_message = "Imagem ${var.image_repository}:${var.image_tag} não encontrada no registry. Confira a tag antes de aplicar."
    }
  }
}
