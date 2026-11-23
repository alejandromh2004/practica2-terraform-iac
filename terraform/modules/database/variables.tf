terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.2"
    }
  }
}

variable "environment" { type = string }
variable "network_name" { type = string }
variable "db_name" { type = string }
variable "db_user" { type = string }
variable "db_password" { type = string }
variable "enable_redis" { 
  type        = bool
  default     = false
  description = "Indica si se despliega Redis (True para PRO, False para DEV)"
}