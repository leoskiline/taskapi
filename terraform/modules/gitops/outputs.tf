output "namespace" {
  value = helm_release.argocd.namespace
}

output "url" {
  description = "Interface do Argo CD"
  value       = "http://${var.argocd_host}"
}

output "admin_password_command" {
  description = "Como obter a senha inicial do admin"
  value       = "kubectl -n ${helm_release.argocd.namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
