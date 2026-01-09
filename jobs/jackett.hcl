job "jackett" {
  datacenters = ["dc1"]
  type        = "service"

  group "jackett" {
    network {
      mode = "bridge"

      port "envoy_metrics" { to = 9102 }
    }

    task "server" {
      driver = "podman"

      config {
        image = "lscr.io/linuxserver/jackett:0.24.521"

        volumes = [
          "/clusterdata/jackett:/config:rw",
        ]
      }

      env {
        PUID = "1000"
        PGID = "1000"
        TZ   = "America/New_York"
      }

      resources {
        cpu    = 100
        memory = 256
      }
    }

    service {
      name = "jackett"
      port = 9117

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
        path     = "/health"
        interval = "10s"
        timeout  = "2s"
        expose   = true
      }
    }
  }
}
