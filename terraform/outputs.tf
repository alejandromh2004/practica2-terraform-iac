output "environment" {
  description = "Workspace de Terraform activo"
  value       = local.env
}

output "webapp_url" {
  description = "URL de acceso a la aplicación Pokédex a través de Nginx"
  value       = "http://localhost:${var.external_port}"
}

output "s3_storage_console" {
  description = "URL del explorador web de objetos S3"
  value       = "http://localhost:${var.minio_console_port}/buckets/${var.bucket_name}/"
}

output "grafana_url" {
  description = "URL de acceso a Grafana (único punto de entrada de observabilidad)"
  value       = var.enable_monitoring ? "http://localhost:3000 (admin / admin)" : "Centralizado en el entorno PRO (http://localhost:3000)"
}
