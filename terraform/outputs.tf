output "cluster_name" {
  value = module.cluster.name
}

output "cluster_endpoint" {
  value = module.cluster.endpoint
}

output "kubectl_context" {
  value = module.cluster.context
}

output "app_url" {
  description = "Onde a aplicação responde"
  value       = "http://taskapi.localtest.me:${var.ingress_host_port}"
}

# Com module.app usando count, os atributos viram lista. try() evita que o
# output quebre quando o módulo está desligado — que é o padrão desde a Fase 7.
output "app_image_digest" {
  description = "Digest resolvido no apply (só quando o Terraform gerencia a app)"
  value       = try(module.app[0].image_digest, "gerenciado pelo Argo CD")
}

output "argocd_url" {
  description = "Interface do Argo CD"
  value       = try("${module.gitops[0].url}:${var.ingress_host_port}", "gitops desligado")
}

output "argocd_admin_password_command" {
  value = try(module.gitops[0].admin_password_command, "gitops desligado")
}

output "grafana_url" {
  value = try("${module.observability[0].grafana_url}:${var.ingress_host_port}", "observabilidade desligada")
}

output "prometheus_port_forward" {
  description = "Prometheus não tem Ingress: acesso por port-forward, de propósito"
  value       = "kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090"
}
