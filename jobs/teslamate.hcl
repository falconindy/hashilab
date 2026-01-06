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

      port "http" {}

      port "envoy_metrics" { to = 9102 }
    }

    restart {
      attempts = 2
      interval = "30m"
      delay    = "15s"
      mode     = "fail"
    }

    ephemeral_disk {
      size = 300
    }

    task "server" {
      driver = "podman"

      config {
        image = "teslamate/teslamate:2.2.0"
        ports = ["http"]
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
        PORT = "${NOMAD_PORT_http}"

        DATABASE_HOST = "localhost"
        DATABASE_PORT = "3000"
        DATABASE_USER = "teslamate"
        DATABASE_NAME = "teslamate"

        MQTT_HOST     = "localhost"
        MQTT_PORT     = "3001"
        MQTT_USERNAME = "teslamate"
      }

      resources {
        cpu    = 200
        memory = 4196
      }
    }

    service {
      name         = "teslamate"
      port         = "http"
      address_mode = "host"

      tags = [
        "traefik.enable=true",
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
            upstreams {
              destination_name = "postgres"
              local_bind_port  = 3000
            }
            upstreams {
              destination_name = "mosquitto"
              local_bind_port  = 3001
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
      }
    }
  }
}
