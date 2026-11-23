output "minio_endpoint" {
  value = "${docker_container.minio.name}:9000"
}

output "bucket_name" {
  value = var.bucket_name
}
