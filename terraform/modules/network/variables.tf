terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.2"
    }
  }
}

variable "environment" {
  type        = string
  description = "Nombre del entorno (dev o pro)"
}