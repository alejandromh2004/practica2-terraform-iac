variable "environment" {
  type        = string
  description = "Nombre del entorno (dev o pro)"
}

variable "network_name" {
  type        = string
  description = "Nombre de la red Docker aislada del entorno"
}

variable "db_name" {
  type        = string
  description = "Nombre de la base de datos PostgreSQL"
}

variable "db_user" {
  type        = string
  description = "Usuario de conexión a PostgreSQL"
}

variable "db_password" {
  type        = string
  description = "Contraseña de PostgreSQL"
  sensitive   = true
}

variable "enable_redis" {
  type        = bool
  default     = false
  description = "Indica si se despliega Redis (true en PRO, false en DEV)"
}
