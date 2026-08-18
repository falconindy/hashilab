job "nut" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "Network UPS Tools monitoring and management daemon"
    link {
      label = "Upstream"
      url   = "https://networkupstools.org"
    }
    link {
      label = "GitHub"
      url   = "https://github.com/networkupstools/nut"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/r/instantlinux/nut-upsd"
    }
  }

  constraint {
    attribute = "${meta.has_ups}"
    operator  = "="
    value     = "true"
  }

  group "nut" {
    network {
      mode = "bridge"

      port "envoy_metrics" { to = 9102 }
    }

    task "server" {
      driver = "docker"

      config {
        image = "instantlinux/nut-upsd:2.8.3-r2"

        devices = [
          {
            host_path      = "/dev/bus/usb",
            container_path = "/dev/bus/usb",
          },
        ]
      }

      env {
        API_PASSWORD = "11111"
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }

    service {
      name = "nut"
      port = 3493

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}"
      }

      connect {
        sidecar_service {}

        sidecar_task {
          resources {
            cpu    = 50
            memory = 48
          }
        }
      }
    }
  }
}
