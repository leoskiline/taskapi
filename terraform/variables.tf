variable "cluster_name" {
  description = "Nome do cluster kind"
  type        = string
  default     = "taskapi"
}

variable "node_image" {
  description = "Imagem do nó do kind — fixa a versão do Kubernetes"
  type        = string
  default     = "kindest/node:v1.36.1"
}

variable "worker_count" {
  description = "Quantidade de workers além do control-plane"
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 1 && var.worker_count <= 5
    error_message = "worker_count deve ficar entre 1 e 5 — acima disso a VM não aguenta."
  }
}

variable "kubeconfig_path" {
  description = "Onde o kubeconfig do cluster é escrito"
  type        = string
  default     = "~/.kube/config"
}

variable "ingress_host_port" {
  description = "Porta da máquina que chega no Ingress do cluster"
  type        = number
  default     = 8081
}

variable "ingress_nginx_version" {
  description = "Versão do chart do ingress-nginx"
  type        = string
  default     = "4.14.1"
}

variable "app_namespace" {
  description = "Namespace da aplicação"
  type        = string
  default     = "taskapi"
}

variable "app_image_repository" {
  description = "Repositório da imagem da aplicação"
  type        = string
  default     = "ghcr.io/leoskiline/taskapi"
}

variable "app_image_tag" {
  description = "Tag da imagem da aplicação — o CI passa o SHA do commit"
  type        = string
  default     = "c52503b"
}

variable "manage_app_with_terraform" {
  description = "Se true, o Terraform instala o chart. Com GitOps ligado deve ser false — os dois gerenciando o mesmo release brigam."
  type        = bool
  default     = false
}

variable "enable_gitops" {
  description = "Instala o Argo CD e cria a Application da taskapi"
  type        = bool
  default     = true
}

variable "argocd_version" {
  description = "Versão do chart do Argo CD"
  type        = string
  default     = "10.2.2"
}

variable "argocd_apps_version" {
  description = "Versão do chart argocd-apps"
  type        = string
  default     = "2.0.5"
}

variable "argocd_host" {
  description = "Hostname do Ingress do Argo CD"
  type        = string
  default     = "argocd.localtest.me"
}

variable "repo_url" {
  description = "Repositório que o Argo CD observa"
  type        = string
  default     = "https://github.com/leoskiline/taskapi.git"
}

variable "target_revision" {
  description = "Branch acompanhada pelo Argo CD"
  type        = string
  default     = "main"
}

variable "enable_observability" {
  description = "Instala kube-prometheus-stack (Prometheus, Alertmanager, Grafana)"
  type        = bool
  default     = true
}

variable "kube_prometheus_stack_version" {
  description = "Versão do chart kube-prometheus-stack"
  type        = string
  default     = "88.0.1"
}

variable "grafana_host" {
  description = "Hostname do Ingress do Grafana"
  type        = string
  default     = "grafana.localtest.me"
}

variable "grafana_password" {
  description = "Senha do admin do Grafana. Laboratório: em produção viria de Secret externo (Fase 9)."
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "metrics_retention" {
  description = "Por quanto tempo o Prometheus guarda as séries"
  type        = string
  default     = "24h"
}

variable "app_environment" {
  description = "Qual values-<env>.yaml do chart usar"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.app_environment)
    error_message = "app_environment deve ser dev ou prod."
  }
}
