output "namespace" {
  value = helm_release.kube_prometheus_stack.namespace
}

output "grafana_url" {
  value = "http://${var.grafana_host}"
}
