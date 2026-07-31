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

module "app" {
  source = "./modules/app"

  release_name     = "taskapi"
  chart_path       = "${path.module}/../charts/taskapi"
  namespace        = module.platform.namespace
  environment      = var.app_environment
  image_repository = var.app_image_repository
  image_tag        = var.app_image_tag

  depends_on = [module.platform]
}
