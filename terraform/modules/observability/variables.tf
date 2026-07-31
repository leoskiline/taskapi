variable "stack_version" {
  type = string
}

variable "namespace" {
  type    = string
  default = "monitoring"
}

variable "retention" {
  type    = string
  default = "24h"
}

variable "storage_size" {
  type    = string
  default = "5Gi"
}

variable "grafana_host" {
  type = string
}

variable "grafana_password" {
  type      = string
  sensitive = true
}

variable "enable_logs" {
  description = "Instala Loki e Promtail"
  type        = bool
  default     = true
}

variable "loki_version" {
  type    = string
  default = "7.2.0"
}

variable "promtail_version" {
  type    = string
  default = "6.17.1"
}

variable "logs_retention" {
  type    = string
  default = "24h"
}
