variable "discord_webhook_url" {
  type        = string
  description = "URL del Webhook de Discord para recibir alertas de Alertmanager"
  default     = ""
  sensitive   = true
}
