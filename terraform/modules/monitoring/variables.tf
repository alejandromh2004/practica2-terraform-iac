variable "environment" {
  type        = string
  description = "Nombre del entorno (dev o pro)"
}

variable "network_name" {
  type        = string
  description = "Nombre de la red Docker del entorno"
}

variable "enable_monitoring" {
  type        = bool
  default     = false
  description = "Activa el despliegue del stack de observabilidad y alertas"
}

variable "discord_webhook_url" {
  type        = string
  default     = ""
  sensitive   = true
  description = "URL del Webhook de Discord para notificaciones de Alertmanager"
}
