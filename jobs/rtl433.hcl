job "rtl433" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${meta.has_rtl433}"
    operator  = "="
    value     = "true"
  }

  group "rtl433" {
    network {
      mode = "bridge"

      port "envoy_metrics" { to = 9102 }
    }

    task "server" {
      driver = "docker"

      config {
        image = "hertzg/rtl_433:25.12-alpine-linux_amd64"

        args = [
          "-c", "${NOMAD_TASK_DIR}/rtl_433.conf",
          "-C", "si",
          "-F", "log",
        ]

        devices = [
          {
            host_path      = "/dev/bus/usb",
            container_path = "/dev/bus/usb",
          },
        ]
      }

      vault {}

      template {
        data        = <<-EOF
          {{ with secret "kv/data/default/rtl433" }}
            output mqtt://mosquitto.virtual.home:80,user=rtl_433,pass={{ .Data.data.mqtt_password }},events=rtl_433[/model][/id]
          {{ end }}
        EOF
        destination = "local/rtl_433.conf"
      }

      resources {
        cpu    = 100
        memory = 64
      }

      env {
        TZ = "America/New_York"
      }
    }

    service {
      name = "rtl433"

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}"
      }

      connect {
        sidecar_service {
          proxy {
            transparent_proxy {}

            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9102"
            }

            expose {
              path {
                path            = "/metrics"
                protocol        = "http"
                local_path_port = 9102
                listener_port   = "envoy_metrics"
              }
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
