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

output "app_image_digest" {
  description = "Digest resolvido no apply — é o que realmente foi implantado"
  value       = module.app.image_digest
}
