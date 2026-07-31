output "name" {
  description = "Nome do cluster"
  value       = kind_cluster.this.name
}

output "endpoint" {
  description = "Endereço do apiserver"
  value       = kind_cluster.this.endpoint
}

output "context" {
  description = "Nome do contexto no kubeconfig"
  value       = "kind-${kind_cluster.this.name}"
}

# Usado por quem depende do cluster para forçar ordenação: um módulo que
# referencia este output só é criado depois que o cluster existe.
output "ready" {
  description = "Sinal de que o cluster terminou de subir"
  value       = kind_cluster.this.id
}
