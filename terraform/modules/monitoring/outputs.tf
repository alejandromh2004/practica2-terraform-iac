output "monitoring_network" {
  value       = var.enable_monitoring ? docker_network.monitoring_internal[0].name : null
  description = "Nombre de la red interna aislada de observabilidad"
}

output "grafana_url" {
  value       = var.enable_monitoring ? "http://localhost:3000" : null
  description = "URL de acceso a Grafana"
}

output "prometheus_url" {
  value       = var.enable_monitoring ? "http://127.0.0.1:9090" : null
  description = "URL local (loopback) de Prometheus"
}
