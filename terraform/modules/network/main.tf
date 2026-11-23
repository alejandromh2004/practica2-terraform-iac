resource "docker_network" "net" {
  name   = "pokedex_${var.environment}_net"
  driver = "bridge"
}