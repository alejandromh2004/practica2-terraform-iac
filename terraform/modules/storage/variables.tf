variable "environment" {
  type        = string
  description = "Nombre del entorno (dev o pro)"
}

variable "network_name" {
  type        = string
  description = "Nombre de la red Docker aislada del entorno"
}

variable "api_port" {
  type        = number
  description = "Puerto externo de la API compatible con AWS S3"
}

variable "console_port" {
  type        = number
  description = "Puerto externo del explorador web de objetos"
}

variable "minio_user" {
  type        = string
  description = "Clave de acceso S3 (Access Key)"
}

variable "minio_password" {
  type        = string
  description = "Clave secreta S3 (Secret Key)"
  sensitive   = true
}

variable "bucket_name" {
  type        = string
  default     = "pokedex-static"
  description = "Nombre del bucket donde se almacenan las imágenes"
}
