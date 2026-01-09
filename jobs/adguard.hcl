job "adguard" {
  datacenters = ["dc1"]
  type        = "service"

  group "adguard" {
    network {
      mode = "bridge"

      port "dns" { to = 53 }

      port "envoy_metrics" { to = 9102 }
    }

    task "server" {
      driver = "podman"

      config {
        image = "adguard/adguardhome:v0.107.71"

        volumes = [
          "/clusterdata/adguard:/opt/adguardhome/conf:rw",
        ]
      }

      env {
        TZ = "America/New_York"
      }

      resources {
        memory = 128
        cpu    = 50
      }
    }

    service {
      name = "adguard-ui"
      port = 80

      check {
        type     = "http"
        path     = "/login.html"
        interval = "10s"
        timeout  = "5s"
        expose   = true
      }

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
    }

    service {
      name = "adguard-dns"
      port = "dns"
    }
  }
}
