job "mqtt-explorer" {
  datacenters = ["dc1"]
  type        = "service"

  group "mqtt-explorer" {
    network {
      mode = "bridge"

      port "envoy_metrics" { to = 9102 }
    }

    task "server" {
      driver = "podman"

      config {
        image = "smeagolworms4/mqtt-explorer:browser-1.0.3"
        volumes = [
          "/clusterdata/mqtt-explorer:/mqtt-explorer/config:rw"
        ]
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }

    service {
      name = "mqtt-explorer"
      port = 4000

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
            transparent_proxy {}

            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9102"
            }

            expose {
              path {
                path = "/metrics"
                protocol = "http"
                local_path_port = 9102
                listener_port = "envoy_metrics"
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
