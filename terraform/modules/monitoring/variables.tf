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
variable "enable_monitoring" {
  type    = bool
  default = false
}
