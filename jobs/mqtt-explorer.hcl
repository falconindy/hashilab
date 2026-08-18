job "mqtt-explorer" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "An all-round MQTT client with a structured topic overview"
    link {
      label = "Upstream"
      url   = "http://mqtt-explorer.com"
    }
    link {
      label = "GitHub"
      url   = "https://github.com/thomasnordquist/MQTT-Explorer"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/r/smeagolworms4/mqtt-explorer"
    }
  }

  group "mqtt-explorer" {
    network {
      mode = "bridge"

      port "envoy_metrics" { to = 9102 }
    }

    task "server" {
      driver = "docker"
      user   = "1000:1000"

      config {
        image = "smeagolworms4/mqtt-explorer:browser-1.0.3"

        cap_drop     = ["all"]
        security_opt = ["no-new-privileges=true"]

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
      ]

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}"
      }

      connect {
        sidecar_service {
          proxy {
            transparent_proxy {}

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
