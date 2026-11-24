output "db_host" {
  value       = docker_container.db.name
  description = "Hostname interno del contenedor PostgreSQL"
}

output "redis_host" {
  value       = var.enable_redis ? docker_container.redis[0].name : null
  description = "Hostname interno de Redis si está habilitado"
}
