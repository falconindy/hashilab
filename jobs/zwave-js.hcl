job "zwave-js" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "Full-featured Z-Wave control panel and MQTT gateway"
    link {
      label = "Upstream"
      url   = "https://zwave-js.github.io/zwave-js-ui/"
    }
    link {
      label = "GitHub"
      url   = "https://github.com/zwave-js/zwave-js-ui"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/r/zwavejs/zwave-js-ui"
    }
  }

  constraint {
    attribute = "${meta.has_zwave}"
    operator  = "="
    value     = "true"
  }

  group "zwave-js" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "envoy_metrics_http" { to = 9102 }
      port "envoy_metrics_ws" { to = 9103 }
    }

    task "server" {
      driver = "docker"

      kill_signal = "SIGINT"

      config {
        image = "zwavejs/zwave-js-ui:11.22.0"

        volumes = [
          "/clusterdata/zwave-js:/usr/src/app/store:rw",
        ]

        devices = [
          {
            host_path      = "/dev/serial/by-id/usb-Zooz_800_Z-Wave_Stick_533D004242-if00",
            container_path = "/dev/zwave",
          },
        ]
      }

      resources {
        cpu    = 100
        memory = 300
      }

      vault {}

      template {
        data        = <<EOF
          {{ with secret "kv/data/default/zwave-js" }}
            SESSION_SECRET="{{ .Data.data.session_secret }}"
          {{ end }}
        EOF
        destination = "secrets/auth.env"
        env         = true
      }
    }

    service {
      name = "zwave-js"
      port = 8091

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=true",
      ]

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics_http}"
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

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
        expose   = true
      }
    }

    service {
      name = "zwave-ws"
      port = 3000

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics_ws}"
      }

      connect {
        sidecar_service {
          proxy {
            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9103"
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
