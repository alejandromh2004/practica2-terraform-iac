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

# 3. Módulo Web & Balanceador de Carga
module "webapp" {
  source        = "./modules/webapp"
  environment   = local.env
  network_name  = module.net.network_name
  
  # DEV: 2 réplicas, puerto externo 5000 | PRO: 3 réplicas, puerto externo 5001
  app_replicas  = local.env == "pro" ? 3 : 2
  external_port = local.env == "pro" ? 5001 : 5000

  db_host       = "${local.env}-postgres"
  db_name       = "practica_db"
  db_user       = "usuario_ejemplo"
  db_password   = "contrasena_segura_aqui"
  
  # Pasa el host de redis solo si estamos en pro
  redis_host    = local.env == "pro" ? "${local.env}-redis" : null

  depends_on = [module.db]
}