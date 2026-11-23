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
  env             = terraform.workspace
  minio_api_port  = local.env == "pro" ? 9010 : 9000
  minio_cons_port = local.env == "pro" ? 9011 : 9001
}

# 1. Módulo de Red
module "net" {
  source      = "./modules/network"
  environment = local.env
}

# 2. Módulo de Base de Datos y Caché
module "db" {
  source       = "./modules/database"
  environment  = local.env
  network_name = module.net.network_name
  db_name      = "practica_db"
  db_user      = "usuario_ejemplo"
  db_password  = "contrasena_segura_aqui"
  enable_redis = local.env == "pro" ? true : false
}

# 3. Módulo de Almacenamiento de Objetos (SeaweedFS / S3)
module "storage" {
  source         = "./modules/storage"
  environment    = local.env
  network_name   = module.net.network_name
  api_port       = local.minio_api_port
  console_port   = local.minio_cons_port
  minio_user     = "minioadmin"
  minio_password = "minioadmin123"
  bucket_name    = "pokedex-static"
}

# 4. Módulo Web & Balanceador de Carga
module "webapp" {
  source        = "./modules/webapp"
  environment   = local.env
  network_name  = module.net.network_name
  app_replicas  = local.env == "pro" ? 3 : 2
  external_port = local.env == "pro" ? 5001 : 5000

  db_host     = "${local.env}-postgres"
  db_name     = "practica_db"
  db_user     = "usuario_ejemplo"
  db_password = "contrasena_segura_aqui"
  redis_host  = local.env == "pro" ? "${local.env}-redis" : null

  minio_endpoint   = module.storage.minio_endpoint
  minio_access_key = "minioadmin"
  minio_secret_key = "minioadmin123"
  minio_bucket     = module.storage.bucket_name
  minio_public_url = "http://localhost:${local.minio_api_port}"

  depends_on = [module.db, module.storage]
}

# 5. Módulo de Observabilidad (Métricas, Logs y Alertas)
module "monitoring" {
  source              = "./modules/monitoring"
  environment         = local.env
  network_name        = module.net.network_name
  enable_monitoring   = local.env == "pro" ? true : false
  discord_webhook_url = var.discord_webhook_url
}
