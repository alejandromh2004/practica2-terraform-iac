# 1. Volumen persistente para el almacenamiento S3
resource "docker_volume" "minio_data" {
  name = "${var.environment}_s3_data"
}

# 2. Imagen oficial de SeaweedFS (Almacenamiento de objetos compatible con AWS S3)
resource "docker_image" "minio" {
  name         = "chrislusf/seaweedfs:latest"
  keep_locally = true
}

# 3. Contenedor Servidor S3 + Interfaz Web Filer
resource "docker_container" "minio" {
  name    = "${var.environment}-s3-storage"
  image   = docker_image.minio.image_id
  restart = "unless-stopped"
  network_mode = "bridge"

  command = [
    "server",
    "-dir=/data",
    "-master.volumeSizeLimitMB=100",
    "-filer",
    "-filer.port=8888",
    "-s3",
    "-s3.port=9000"
  ]

  # Puerto API S3 (9000 en DEV, 9010 en PRO)
  ports {
    internal = 9000
    external = var.api_port
  }

  # Puerto Consola Web para explorar archivos (9001 en DEV, 9011 en PRO)
  ports {
    internal = 8888
    external = var.console_port
  }

  networks_advanced {
    name = var.network_name
  }

  volumes {
    container_path = "/data"
    volume_name    = docker_volume.minio_data.name
  }
}
