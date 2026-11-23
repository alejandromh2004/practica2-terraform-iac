variable "app_replicas" {
  type        = number
  description = "Número de réplicas de la aplicación Flask detrás del balanceador Nginx"
}

variable "external_port" {
  type        = number
  description = "Puerto externo expuesto por el balanceador de carga Nginx"
}

variable "enable_redis" {
  type        = bool
  description = "Habilita el contenedor de caché Redis"
}

variable "enable_monitoring" {
  type        = bool
  description = "Despliega el stack centralizado de observabilidad y alertas"
}

variable "minio_api_port" {
  type        = number
  description = "Puerto externo de la API compatible con AWS S3"
}

variable "minio_console_port" {
  type        = number
  description = "Puerto externo de la interfaz web del almacenamiento S3"
}

variable "db_name" {
  type    = string
  default = "practica_db"
}

variable "db_user" {
  type    = string
  default = "pokedex_app_user"
}

variable "db_password" {
  type        = string
  description = "Contraseña de PostgreSQL (definida en secret.auto.tfvars)"
  sensitive   = true
}

variable "minio_user" {
  type    = string
  default = "pokedex_s3_admin"
}

variable "minio_password" {
  type        = string
  description = "Clave secreta del almacenamiento S3 (definida en secret.auto.tfvars)"
  sensitive   = true
}

variable "bucket_name" {
  type    = string
  default = "pokedex-static"
}

variable "discord_webhook_url" {
  type        = string
  description = "URL del Webhook de Discord para Alertmanager (definida en secret.auto.tfvars)"
  default     = ""
  sensitive   = true
}
