output "namespace" {
  description = "Namespace criado para a aplicação"
  value       = kubernetes_namespace.app.metadata[0].name
}

output "ingress_ready" {
  description = "Sinal de que o ingress controller está instalado"
  value       = helm_release.ingress_nginx.status
}
