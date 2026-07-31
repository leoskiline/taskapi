# Raiz: só amarra os três módulos. A lógica mora neles.
#
# A separação não é enfeite — é o que permite `terraform apply
# -target=module.app` numa emergência sem arriscar recriar o cluster inteiro,
# e é o desenho que a Fase 10 reaproveita trocando o módulo de cluster por um
# de EKS/AKS/GKE, com os outros dois intactos.

module "cluster" {
  source = "./modules/cluster"

  cluster_name      = var.cluster_name
  node_image        = var.node_image
  worker_count      = var.worker_count
  ingress_host_port = var.ingress_host_port
}

module "platform" {
  source = "./modules/platform"

  ingress_nginx_version = var.ingress_nginx_version
  app_namespace         = var.app_namespace

  # depends_on explícito no módulo: sem isto o Terraform tentaria falar com um
  # apiserver que ainda não existe. A dependência implícita não existe porque
  # os providers apontam para um caminho de kubeconfig, não para atributos do
  # recurso do cluster.
  depends_on = [module.cluster]
}

# A partir da Fase 7 a aplicação passa a ser implantada pelo Argo CD, não pelo
# Terraform. Deixar os dois gerenciando o mesmo release seria briga garantida:
# o Argo reconcilia contra o git a cada 3 minutos, o Terraform contra o state —
# e cada `apply` desfaria o que o outro fez.
#
# A fronteira fica assim: Terraform cuida do cluster e da plataforma; o Argo
# cuida do que roda em cima. count mantém o caminho antigo disponível para
# comparar os dois modelos.
module "app" {
  source = "./modules/app"
  count  = var.manage_app_with_terraform ? 1 : 0

  release_name     = "taskapi"
  chart_path       = "${path.module}/../charts/taskapi"
  namespace        = module.platform.namespace
  environment      = var.app_environment
  image_repository = var.app_image_repository
  image_tag        = var.app_image_tag

  depends_on = [module.platform]
}

module "observability" {
  source = "./modules/observability"
  count  = var.enable_observability ? 1 : 0

  stack_version    = var.kube_prometheus_stack_version
  grafana_host     = var.grafana_host
  grafana_password = var.grafana_password
  retention        = var.metrics_retention

  depends_on = [module.platform]
}

module "gitops" {
  source = "./modules/gitops"
  count  = var.enable_gitops ? 1 : 0

  argocd_version      = var.argocd_version
  argocd_apps_version = var.argocd_apps_version
  argocd_host         = var.argocd_host
  repo_url            = var.repo_url
  target_revision     = var.target_revision
  environment         = var.app_environment
  app_namespace       = module.platform.namespace

  depends_on = [module.platform]
}
