variable "environment" {
  type        = string
  description = "Nombre del entorno (dev o pro)"
}

variable "network_name" {
  type        = string
  description = "Nombre de la red Docker aislada del entorno"
}

variable "app_replicas" {
  type        = number
  description = "Número de contenedores réplica de Flask"
}

variable "external_port" {
  type        = number
  description = "Puerto externo expuesto por el balanceador Nginx"
}

variable "db_host" {
  type        = string
  description = "Hostname interno del contenedor PostgreSQL"
}

variable "db_name" {
  type        = string
  description = "Nombre de la base de datos PostgreSQL"
}

variable "db_user" {
  type        = string
  description = "Usuario de PostgreSQL"
}

variable "db_password" {
  type        = string
  description = "Contraseña de PostgreSQL"
  sensitive   = true
}

variable "redis_host" {
  type        = string
  default     = null
  description = "Hostname interno de Redis (null si está desactivado)"
}

variable "minio_endpoint" {
  type        = string
  description = "Endpoint interno (host:puerto) del servicio S3"
}

variable "minio_access_key" {
  type        = string
  description = "Access Key para el cliente S3"
}

variable "minio_secret_key" {
  type        = string
  description = "Secret Key para el cliente S3"
  sensitive   = true
}

variable "minio_bucket" {
  type        = string
  description = "Bucket S3 de destino"
}

variable "minio_public_url" {
  type        = string
  description = "URL accesible desde el navegador para cargar imágenes S3"
}
