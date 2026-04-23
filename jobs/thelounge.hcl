job "thelounge" {
  datacenters = ["dc1"]
  type        = "service"

  group "thelounge" {
    network {
      mode = "bridge"

      port "envoy_metrics" { to = 9102 }
    }

    task "server" {
      driver = "docker"

      config {
        image = "ghcr.io/thelounge/thelounge:4.4.3"

        volumes = [
          "/clusterdata/thelounge:/var/opt/thelounge"
        ]
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }

    service {
      name = "irc"
      port = 9000

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
  }
}
