variable "argocd_version" {
  type = string
}

variable "argocd_apps_version" {
  type = string
}

variable "argocd_host" {
  type = string
}

variable "repo_url" {
  description = "Repositório que o Argo observa"
  type        = string
}

variable "target_revision" {
  description = "Branch ou tag acompanhada"
  type        = string
}

variable "environment" {
  description = "Qual gitops/environments/<env>/values.yaml usar"
  type        = string
}

variable "app_namespace" {
  type = string
}
