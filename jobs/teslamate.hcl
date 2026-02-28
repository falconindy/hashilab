job "teslamate" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "A datalogger for your Tesla"
    link {
      label = "Teslamate Docs"
      url   = "https://docs.teslamate.org"
    }
    link {
      label = "GitHub"
      url   = "https://github.com/teslamate-org/teslamate"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/r/teslamate/teslamate"
    }
  }

  group "teslamate" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "envoy_metrics" { to = 9102 }
    }

    task "server" {
      driver = "docker"

      config {
        image = "teslamate/teslamate:3.0.0"
      }

      vault {}

      template {
        data        = <<EOF
          {{ with secret "kv/data/default/teslamate" }}
            ENCRYPTION_KEY="{{ .Data.data.encryption_key }}"
            DATABASE_PASS="{{ .Data.data.postgres_password }}" 
            MQTT_PASSWORD="{{ .Data.data.mqtt_password }}"
          {{ end }}
        EOF
        destination = "secrets/auth.env"
        env         = true
      }

      env {
        PORT = 8080

        DATABASE_HOST = "postgres.virtual.home"
        DATABASE_PORT = "80"
        DATABASE_USER = "teslamate"
        DATABASE_NAME = "teslamate"

        MQTT_HOST     = "mosquitto.virtual.home"
        MQTT_PORT     = "80"
        MQTT_USERNAME = "teslamate"
      }

      resources {
        cpu    = 200
        memory = 1024
      }
    }

    service {
      name = "teslamate"
      port = 8080

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
            transparent_proxy {
              # Teslamate makes calls to the outside world.
              no_dns = true
            }

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
