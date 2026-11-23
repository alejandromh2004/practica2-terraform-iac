# 0. Redes aisladas para Observabilidad (Segmentación de tráfico)
resource "docker_network" "monitoring_internal" {
  count    = var.enable_monitoring ? 1 : 0
  name     = "${var.environment}_monitoring_net"
  driver   = "bridge"
  internal = true
}

resource "docker_network" "monitoring_egress" {
  count  = var.enable_monitoring ? 1 : 0
  name   = "${var.environment}_monitoring_egress"
  driver = "bridge"
}

# 1. cAdvisor (Solo accesible en red interna de monitorización, sin puertos externos)
resource "docker_image" "cadvisor" {
  count        = var.enable_monitoring ? 1 : 0
  name         = "gcr.io/cadvisor/cadvisor:v0.49.1"
  keep_locally = true
}

resource "docker_container" "cadvisor" {
  count      = var.enable_monitoring ? 1 : 0
  name       = "${var.environment}-cadvisor"
  image      = docker_image.cadvisor[0].image_id
  restart    = "unless-stopped"
  privileged = true
  command    = ["--docker_only=true"]

  networks_advanced {
    name = docker_network.monitoring_internal[0].name
  }

  volumes {
    container_path = "/rootfs"
    host_path      = "/"
    read_only      = true
  }
  volumes {
    container_path = "/var/run"
    host_path      = "/var/run"
    read_only      = false
  }
  volumes {
    container_path = "/sys"
    host_path      = "/sys"
    read_only      = true
  }
  volumes {
    container_path = "/var/lib/docker"
    host_path      = "/var/lib/docker"
    read_only      = true
  }
}

# 2. Prometheus (Solo accesible por Grafana y Alertmanager en red interna)
resource "docker_image" "prometheus" {
  count        = var.enable_monitoring ? 1 : 0
  name         = "prom/prometheus:v2.53.0"
  keep_locally = true
}

resource "docker_container" "prometheus" {
  count   = var.enable_monitoring ? 1 : 0
  name    = "${var.environment}-prometheus"
  image   = docker_image.prometheus[0].image_id
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.monitoring_internal[0].name
  }

  volumes {
    container_path = "/etc/prometheus/prometheus.yml"
    host_path      = abspath("${path.module}/../../../config/prometheus/prometheus.yml")
    read_only      = true
  }
  volumes {
    container_path = "/etc/prometheus/alert_rules.yml"
    host_path      = abspath("${path.module}/../../../config/prometheus/alert_rules.yml")
    read_only      = true
  }

  depends_on = [docker_container.cadvisor]
}

# 3. Loki (Solo accesible por Alloy y Grafana en red interna)
resource "docker_image" "loki" {
  count        = var.enable_monitoring ? 1 : 0
  name         = "grafana/loki:3.1.0"
  keep_locally = true
}

resource "docker_container" "loki" {
  count   = var.enable_monitoring ? 1 : 0
  name    = "${var.environment}-loki"
  image   = docker_image.loki[0].image_id
  restart = "unless-stopped"
  command = ["-config.file=/etc/loki/local-config.yaml"]

  networks_advanced {
    name = docker_network.monitoring_internal[0].name
  }

  volumes {
    container_path = "/etc/loki/local-config.yaml"
    host_path      = abspath("${path.module}/../../../config/loki/loki-config.yml")
    read_only      = true
  }
}

# 4. Grafana Alloy (Solo red interna, envía logs a Loki)
resource "docker_image" "alloy" {
  count        = var.enable_monitoring ? 1 : 0
  name         = "grafana/alloy:v1.3.1"
  keep_locally = true
}

resource "docker_container" "alloy" {
  count   = var.enable_monitoring ? 1 : 0
  name    = "${var.environment}-alloy"
  image   = docker_image.alloy[0].image_id
  restart = "unless-stopped"
  user    = "root"
  command = ["run", "--server.http.listen-addr=0.0.0.0:12345", "--storage.path=/var/lib/alloy/data", "/etc/alloy/config.alloy"]

  networks_advanced {
    name = docker_network.monitoring_internal[0].name
  }

  volumes {
    container_path = "/etc/alloy/config.alloy"
    host_path      = abspath("${path.module}/../../../config/alloy/config.alloy")
    read_only      = true
  }
  volumes {
    container_path = "/var/run/docker.sock"
    host_path      = "/var/run/docker.sock"
    read_only      = true
  }

  depends_on = [docker_container.loki]
}

# 5. Grafana (Único punto de entrada expuesto con autenticación)
resource "docker_image" "grafana" {
  count        = var.enable_monitoring ? 1 : 0
  name         = "grafana/grafana:11.1.0"
  keep_locally = true
}

resource "docker_container" "grafana" {
  count   = var.enable_monitoring ? 1 : 0
  name    = "${var.environment}-grafana"
  image   = docker_image.grafana[0].image_id
  restart = "unless-stopped"

  env = [
    "GF_SECURITY_ADMIN_USER=admin",
    "GF_SECURITY_ADMIN_PASSWORD=admin",
    "GF_USERS_ALLOW_SIGN_UP=false"
  ]

  ports {
    internal = 3000
    external = 3000
  }

  networks_advanced {
    name = docker_network.monitoring_internal[0].name
  }
  networks_advanced {
    name = docker_network.monitoring_egress[0].name
  }

  volumes {
    container_path = "/etc/grafana/provisioning"
    host_path      = abspath("${path.module}/../../../config/grafana/provisioning")
    read_only      = true
  }
  volumes {
    container_path = "/var/lib/grafana/dashboards"
    host_path      = abspath("${path.module}/../../../config/grafana/dashboards")
    read_only      = true
  }

  depends_on = [docker_container.prometheus, docker_container.loki]
}

# 6. Alertmanager (Sin puertos entrantes; recibe de red interna y sale a Discord)
resource "local_file" "alertmanager_conf" {
  count = var.enable_monitoring ? 1 : 0
  content = templatefile("${path.module}/../../../config/alertmanager/alertmanager.yml.tftpl", {
    discord_webhook_url = var.discord_webhook_url
  })
  filename = "${path.module}/../../.terraform/alertmanager_${var.environment}.yml"
}

resource "docker_image" "alertmanager" {
  count        = var.enable_monitoring ? 1 : 0
  name         = "prom/alertmanager:v0.27.0"
  keep_locally = true
}

resource "docker_container" "alertmanager" {
  count   = var.enable_monitoring ? 1 : 0
  name    = "${var.environment}-alertmanager"
  image   = docker_image.alertmanager[0].image_id
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.monitoring_internal[0].name
  }
  networks_advanced {
    name = docker_network.monitoring_egress[0].name
  }

  volumes {
    container_path = "/etc/alertmanager/alertmanager.yml"
    host_path      = abspath(local_file.alertmanager_conf[0].filename)
    read_only      = true
  }

  depends_on = [docker_container.prometheus]
}
