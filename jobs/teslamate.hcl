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

      service {
        name         = "teslamate"
        port         = "http"
        address_mode = "host"
        tags = [
          "traefik.enable=true",
        ]

        check {
          type     = "tcp"
          port     = "http"
          interval = "30s"
          timeout  = "2s"
        }
      }

      vault {}

      identity {
        name = "vault_default"
        aud  = ["vault.io"]
        ttl  = "1h"
      }

      template {
        data        = <<EOH
          {{ with secret "kv/data/default/teslamate" }}
            ENCRYPTION_KEY="{{ .Data.data.encryption_key }}"
            DATABASE_PASS="{{ .Data.data.postgres_password }}" 
            MQTT_PASSWORD="{{ .Data.data.mqtt_password }}"
          {{ end }}
        EOH
        destination = "secrets/auth.env"
        env         = true
      }

      env {
        PORT = "${NOMAD_PORT_http}"

        DATABASE_HOST = "postgres.service.home"
        DATABASE_USER = "teslamate"
        DATABASE_NAME = "teslamate"

        MQTT_HOST     = "mosquitto.service.home"
        MQTT_USERNAME = "teslamate"
      }

      resources {
        cpu    = 200
        memory = 4196
      }
    }
  }
}
