terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}

# kube-prometheus-stack: Prometheus Operator, Prometheus, Alertmanager,
# Grafana, node-exporter e kube-state-metrics em um chart só.
#
# Os recursos abaixo estão bem abaixo do padrão do chart, de propósito: a VM
# tem 4 vCPU e 7,7 GB e já roda kind com 3 nós, Argo CD e Postgres. Em um
# cluster real esses números seriam irresponsáveis — aqui, sem eles, o stack
# não sobe.
resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.stack_version

  namespace        = var.namespace
  create_namespace = true

  wait    = true
  timeout = 1200

  values = [
    yamlencode({
      prometheus = {
        prometheusSpec = {
          retention = var.retention
          # Sem seletor por label, o Prometheus só descobre ServiceMonitors
          # que tenham `release: <nome-do-release>`. Manter o padrão obriga o
          # chart da aplicação a se identificar — o que é bom: evita que
          # qualquer Service do cluster vire alvo por acidente.
          serviceMonitorSelectorNilUsesHelmValues = true
          ruleSelectorNilUsesHelmValues           = true
          resources = {
            requests = { cpu = "100m", memory = "512Mi" }
            limits   = { memory = "1500Mi" }
          }
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                accessModes = ["ReadWriteOnce"]
                resources   = { requests = { storage = var.storage_size } }
              }
            }
          }
        }
      }

      alertmanager = {
        alertmanagerSpec = {
          resources = {
            requests = { cpu = "10m", memory = "64Mi" }
            limits   = { memory = "128Mi" }
          }
        }
      }

      grafana = {
        adminPassword = var.grafana_password
        ingress = {
          enabled          = true
          ingressClassName = "nginx"
          hosts            = [var.grafana_host]
          path             = "/"
          pathType         = "Prefix"
        }
        resources = {
          requests = { cpu = "50m", memory = "128Mi" }
          limits   = { memory = "256Mi" }
        }
        # Dashboards versionados no repositório entram como ConfigMap e são
        # carregados no boot. Dashboard editado na UI e não exportado é
        # trabalho que se perde no próximo redeploy.
        sidecar = {
          dashboards = {
            enabled         = true
            label           = "grafana_dashboard"
            searchNamespace = "ALL"
          }
        }
      }

      # node-exporter e kube-state-metrics ficam: são eles que respondem
      # "saturação" nos quatro sinais de ouro, no nível do nó e do cluster.
      nodeExporter     = { enabled = true }
      kubeStateMetrics = { enabled = true }

      # Componentes do control-plane que o kind não expõe da forma esperada.
      # Deixá-los ligados só produziria alvos permanentemente vermelhos, que
      # é a maneira mais rápida de ensinar um time a ignorar alertas.
      kubeEtcd              = { enabled = false }
      kubeControllerManager = { enabled = false }
      kubeScheduler         = { enabled = false }
      kubeProxy             = { enabled = false }
    })
  ]
}

# O dashboard fica no git e é carregado pelo sidecar do Grafana.
resource "kubernetes_config_map" "dashboard" {
  metadata {
    name      = "taskapi-dashboard"
    namespace = var.namespace
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "taskapi.json" = file("${path.module}/dashboards/taskapi.json")
  }

  depends_on = [helm_release.kube_prometheus_stack]
}
