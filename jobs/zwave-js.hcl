job "zwave-js" {
  datacenters = ["dc1"]
  type        = "service"

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

      port "ws" {
        static = 3000
      }

      port "envoy_metrics" { to = 9102 }
    }

    task "server" {
      driver = "podman"

      kill_signal = "SIGINT"

      config {
        image = "zwavejs/zwave-js-ui:11.9.1"
        ports = ["ws"]

        volumes = [
          "/clusterdata/zwave-js:/usr/src/app/store:rw",
        ]

        devices = [
          "/dev/serial/by-id/usb-Zooz_800_Z-Wave_Stick_533D004242-if00:/dev/zwave:rw",
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
      name         = "zwave-js"
      port         = 8091

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=true",
      ]

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

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
        expose   = true
      }
    }
  }
}
