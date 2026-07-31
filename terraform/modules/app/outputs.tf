output "release" {
  description = "Nome do release instalado"
  value       = helm_release.app.name
}

output "revision" {
  description = "Revisão atual do release"
  value       = helm_release.app.version
}

output "image_digest" {
  description = "Digest da imagem que a tag apontava no momento do apply"
  value       = data.docker_registry_image.app.sha256_digest
}
