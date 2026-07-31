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

variable "app_environment" {
  description = "Qual values-<env>.yaml do chart usar"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.app_environment)
    error_message = "app_environment deve ser dev ou prod."
  }
}
