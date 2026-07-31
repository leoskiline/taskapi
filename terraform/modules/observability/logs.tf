# Loki: o mesmo modelo do Prometheus, aplicado a log. Ele não indexa o
# conteúdo da linha — só os labels (namespace, pod, container). É isso que o
# torna barato o suficiente para caber nesta VM, e é também por isso que o log
# estruturado em JSON da Fase 1 importa: sem campos, a consulta vira regex.

resource "helm_release" "loki" {
  count = var.enable_logs ? 1 : 0

  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = var.loki_version

  namespace = var.namespace

  wait    = true
  timeout = 900

  values = [
    yamlencode({
      # Modo binário único: um pod em vez dos ~8 do modo distribuído.
      deploymentMode = "SingleBinary"

      loki = {
        auth_enabled = false
        commonConfig = { replication_factor = 1 }
        storage      = { type = "filesystem" }
        schemaConfig = {
          configs = [{
            from         = "2024-04-01"
            store        = "tsdb"
            object_store = "filesystem"
            schema       = "v13"
            index        = { prefix = "index_", period = "24h" }
          }]
        }
        limits_config = {
          retention_period   = var.logs_retention
          reject_old_samples = false
        }
      }

      singleBinary = {
        replicas    = 1
        persistence = { enabled = true, size = "5Gi" }
        resources = {
          requests = { cpu = "50m", memory = "256Mi" }
          limits   = { memory = "512Mi" }
        }
      }

      # Tudo que pertence ao modo distribuído fica zerado. Sem isto o chart
      # sobe memcached, gateway e três StatefulSets que a VM não aguenta.
      read         = { replicas = 0 }
      write        = { replicas = 0 }
      backend      = { replicas = 0 }
      chunksCache  = { enabled = false }
      resultsCache = { enabled = false }
      gateway      = { enabled = false }
      lokiCanary   = { enabled = false }
      test         = { enabled = false }
      minio        = { enabled = false }
    })
  ]
}

# Promtail: um DaemonSet que lê /var/log/pods de cada nó e empurra para o Loki.
resource "helm_release" "promtail" {
  count = var.enable_logs ? 1 : 0

  name       = "promtail"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"
  version    = var.promtail_version

  namespace = var.namespace

  wait    = true
  timeout = 600

  values = [
    yamlencode({
      config = {
        clients = [{
          url = "http://loki.${var.namespace}.svc:3100/loki/api/v1/push"
        }]
      }
      resources = {
        requests = { cpu = "20m", memory = "64Mi" }
        limits   = { memory = "128Mi" }
      }
    })
  ]

  depends_on = [helm_release.loki]
}

# Datasource do Loki no Grafana, entregue por ConfigMap.
#
# O sidecar do Grafana observa ConfigMaps com este label e recarrega sozinho —
# mesma mecânica do dashboard. Datasource criado na UI sumiria no próximo
# redeploy do pod.
resource "kubernetes_config_map" "loki_datasource" {
  count = var.enable_logs ? 1 : 0

  metadata {
    name      = "loki-datasource"
    namespace = var.namespace
    labels = {
      grafana_datasource = "1"
    }
  }

  data = {
    "loki-datasource.yaml" = yamlencode({
      apiVersion = 1
      datasources = [{
        name      = "Loki"
        type      = "loki"
        access    = "proxy"
        url       = "http://loki.${var.namespace}.svc:3100"
        isDefault = false
      }]
    })
  }

  depends_on = [helm_release.loki]
}
