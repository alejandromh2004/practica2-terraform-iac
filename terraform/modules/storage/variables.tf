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
variable "api_port" { type = number }
variable "console_port" { type = number }
variable "minio_user" { type = string }
variable "minio_password" { type = string }
variable "bucket_name" {
  type    = string
  default = "pokedex-static"
}
