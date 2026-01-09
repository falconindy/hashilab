job "teslamate" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "Teslamate"
    link {
      label = "Teslamate Docs"
      url   = "https://docs.teslamate.org"
    }
  }

  group "teslamate" {
    count = 1

    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "envoy_metrics" { to = 9102 }
    }

    restart {
      attempts = 2
      interval = "30m"
      delay    = "15s"
      mode     = "fail"
    }

    task "server" {
      driver = "podman"

      config {
        image = "teslamate/teslamate:2.2.0"
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
        memory = 4196
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
