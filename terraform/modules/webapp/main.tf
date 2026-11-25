# 1. Construcción de la imagen Docker de la App Flask
resource "docker_image" "app" {
  name = "pokedex-app:${var.environment}"
  build {
    context    = abspath("${path.module}/../../../app")
    dockerfile = "Dockerfile"
  }
  triggers = {
    dir_sha1 = sha1(join("", [for f in fileset("${path.module}/../../../app", "**") : filesha1("${path.module}/../../../app/${f}")]))
  }
}

# 2. Despliegue de las réplicas de Flask
resource "docker_container" "app_replicas" {
  count        = var.app_replicas
  name         = "${var.environment}-app-${count.index + 1}"
  hostname     = "${var.environment}-app-${count.index + 1}"
  image        = docker_image.app.image_id
  restart      = "unless-stopped"
  network_mode = "bridge"

  env = concat(
    [
      "DB_HOST=${var.db_host}",
      "DB_NAME=${var.db_name}",
      "DB_USER=${var.db_user}",
      "DB_PASSWORD=${var.db_password}",
      "DB_PORT=5432",
      "MINIO_ENDPOINT=${var.minio_endpoint}",
      "MINIO_ACCESS_KEY=${var.minio_access_key}",
      "MINIO_SECRET_KEY=${var.minio_secret_key}",
      "MINIO_BUCKET=${var.minio_bucket}",
      "MINIO_PUBLIC_URL=${var.minio_public_url}"
    ],
    var.redis_host != null ? [
      "REDIS_HOST=${var.redis_host}",
      "REDIS_PORT=6379"
    ] : []
  )

  networks_advanced {
    name = var.network_name
  }
}

# 3. Imagen de Nginx para el Balanceador
resource "docker_image" "nginx" {
  name         = "nginx:latest"
  keep_locally = true
}

# 4. Generación dinámica del archivo de configuración Nginx
resource "local_file" "nginx_conf" {
  content = templatefile("${path.module}/../../../config/nginx/lb.conf.tftpl", {
    backend_names = docker_container.app_replicas[*].name
  })
  filename = "${path.module}/../../.terraform/nginx_${var.environment}.conf"
}

# 5. Contenedor Balanceador de Carga Nginx (se recrea automáticamente al cambiar local_file.nginx_conf)
resource "docker_container" "load_balancer" {
  name         = "${var.environment}-load-balancer"
  image        = docker_image.nginx.image_id
  restart      = "unless-stopped"
  network_mode = "bridge"

  ports {
    internal = 80
    external = var.external_port
  }

  networks_advanced {
    name = var.network_name
  }

  volumes {
    container_path = "/etc/nginx/nginx.conf"
    host_path      = abspath(local_file.nginx_conf.filename)
    read_only      = true
  }

  lifecycle {
    replace_triggered_by = [
      local_file.nginx_conf
    ]
  }

  depends_on = [docker_container.app_replicas, local_file.nginx_conf]
}
