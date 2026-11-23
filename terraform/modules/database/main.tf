# Volumen persistente para PostgreSQL (separado por entorno)
resource "docker_volume" "db_data" {
  name = "${var.environment}_db_data"
}

# Imagen de PostgreSQL 15
resource "docker_image" "postgres" {
  name         = "postgres:15-alpine"
  keep_locally = true
}

# Contenedor PostgreSQL
resource "docker_container" "db" {
  name  = "${var.environment}-postgres"
  image = docker_image.postgres.image_id
  restart = "unless-stopped"

  env = [
    "POSTGRES_DB=${var.db_name}",
    "POSTGRES_USER=${var.db_user}",
    "POSTGRES_PASSWORD=${var.db_password}"
  ]

  networks_advanced {
    name = var.network_name
  }

  volumes {
    container_path = "/var/lib/postgresql/data"
    volume_name    = docker_volume.db_data.name
  }

  # Montaje del script inicial desde la raíz del proyecto (../../../init.sql)
  volumes {
    container_path = "/docker-entrypoint-initdb.d/init.sql"
    host_path      = abspath("${path.module}/../../../init.sql")
    read_only      = true
  }

  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U ${var.db_user} -d ${var.db_name}"]
    interval = "5s"
    timeout  = "5s"
    retries  = 5
  }
}

# Imagen de Redis 7
resource "docker_image" "redis" {
  count        = var.enable_redis ? 1 : 0
  name         = "redis:7-alpine"
  keep_locally = true
}

# Contenedor Redis (Condicional: count = 1 en PRO, 0 en DEV)
resource "docker_container" "redis" {
  count   = var.enable_redis ? 1 : 0
  name    = "${var.environment}-redis"
  image   = docker_image.redis[0].image_id
  restart = "unless-stopped"

  networks_advanced {
    name = var.network_name
  }

  healthcheck {
    test     = ["CMD", "redis-cli", "ping"]
    interval = "5s"
    timeout  = "3s"
    retries  = 5
  }
}