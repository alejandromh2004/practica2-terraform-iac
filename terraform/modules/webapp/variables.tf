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
variable "minio_endpoint" { type = string }
variable "minio_access_key" { type = string }
variable "minio_secret_key" { type = string }
variable "minio_bucket" { type = string }
variable "minio_public_url" { type = string }
