job "nut" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${meta.has_ups}"
    operator  = "="
    value     = "true"
  }

  group "nut" {
    count = 1

    network {
      mode = "bridge"

      port "envoy_metrics" { to = 9102 }
    }

    task "server" {
      driver = "podman"

      config {
        image = "instantlinux/nut-upsd:2.8.3-r2"

        devices = [
          "/dev/bus/usb:/dev/bus/usb:rw",
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
        sidecar_service {
          proxy {
            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9102"
            }
          }
        }

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
