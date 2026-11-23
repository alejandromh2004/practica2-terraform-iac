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
variable "app_replicas" { type = number }
variable "external_port" { type = number }
variable "db_host" { type = string }
variable "db_name" { type = string }
variable "db_user" { type = string }
variable "db_password" { type = string }
variable "redis_host" { 
  type    = string
  default = null 
}