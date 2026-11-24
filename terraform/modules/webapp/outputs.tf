output "load_balancer_url" {
  value       = "http://localhost:${var.external_port}"
  description = "URL externa del balanceador Nginx"
}

output "replica_names" {
  value       = docker_container.app_replicas[*].name
  description = "Lista de nombres de los contenedores réplica activos"
}
