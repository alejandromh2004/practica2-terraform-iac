terraform {
  required_version = ">= 1.0.0"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.2"
    }
  }
}

provider "docker" {}

locals {
  env = terraform.workspace
}

# 1. Módulo de Red aislada por entorno
module "net" {
  source      = "./modules/network"
  environment = local.env
}

# 2. Módulo de Base de Datos (PostgreSQL) y Caché (Redis en PRO)
module "db" {
  source       = "./modules/database"
  environment  = local.env
  network_name = module.net.network_name
  db_name      = var.db_name
  db_user      = var.db_user
  db_password  = var.db_password
  enable_redis = var.enable_redis
}

# 3. Módulo de Almacenamiento de Objetos compatible con AWS S3 (SeaweedFS)
module "storage" {
  source         = "./modules/storage"
  environment    = local.env
  network_name   = module.net.network_name
  api_port       = var.minio_api_port
  console_port   = var.minio_console_port
  minio_user     = var.minio_user
  minio_password = var.minio_password
  bucket_name    = var.bucket_name
}

# 4. Módulo Web (Réplicas Flask + Balanceador Round-Robin Nginx)
module "webapp" {
  source        = "./modules/webapp"
  environment   = local.env
  network_name  = module.net.network_name
  app_replicas  = var.app_replicas
  external_port = var.external_port

  db_host     = "${local.env}-postgres"
  db_name     = var.db_name
  db_user     = var.db_user
  db_password = var.db_password
  redis_host  = var.enable_redis ? "${local.env}-redis" : null

  minio_endpoint   = module.storage.minio_endpoint
  minio_access_key = var.minio_user
  minio_secret_key = var.minio_password
  minio_bucket     = module.storage.bucket_name
  minio_public_url = "http://localhost:${var.minio_api_port}"

  depends_on = [module.db, module.storage]
}

# 5. Módulo de Observabilidad y Alertas (Red interna aislada + Grafana + Discord)
module "monitoring" {
  source              = "./modules/monitoring"
  environment         = local.env
  network_name        = module.net.network_name
  enable_monitoring   = var.enable_monitoring
  discord_webhook_url = var.discord_webhook_url
}
