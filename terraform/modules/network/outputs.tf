output "network_name" {
  value       = docker_network.net.name
  description = "Nombre de la red de Docker creada"
}