job "teslamate" {
  datacenters = ["dc1"]
  type        = "service"

  #update {
  #  max_parallel      = 1
  #  min_healthy_time  = "10s"
  #  healthy_deadline  = "3m"
  #  progress_deadline = "10m"
  #  auto_revert       = false
  #  canary            = 0
  #}

  #migrate {
  #  max_parallel     = 1
  #  health_check     = "checks"
  #  min_healthy_time = "10s"
  #  healthy_deadline = "5m"
  #}

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
      port "http" {
        to = 4000
      }

      dns {
        servers = ["172.17.0.1"]
      }
    }

    service {
      name = "teslamate"
      port = "http"

      check {
        type     = "tcp"
        port     = "http"
        interval = "30s"
        timeout  = "2s"
      }
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
      driver = "docker"

      config {
        image = "teslamate/teslamate:1.32"
        ports = ["http"]
      }

      vault {}

      identity {
        name = "vault_default"
        aud = ["vault.io"]
        ttl = "1h"
      }

      template {
        data = <<EOH
          {{ with secret "kv/data/default/teslamate" }}
            ENCRYPTION_KEY="{{ .Data.data.encryption_key }}"
            DATABASE_PASS="{{ .Data.data.postgres_password }}" 
            MQTT_PASSWORD="{{ .Data.data.mqtt_password }}"
          {{ end }}
        EOH
        destination = "secrets/auth.env"
        env = true
      }

      env {
        #ENCRYPTION_KEY = "wUyIHr3AYH7THzzzBhS3IO/JJO+6wWbAJlragenbzicT0MleDFmCWu"

        DATABASE_HOST = "postgres.service.consul"
        DATABASE_USER = "teslamate"
        #DATABASE_PASS = "46b3183d070e3aa18f0984e9e798eafc"
        DATABASE_NAME = "teslamate"

        MQTT_HOST     = "mosquitto.service.consul"
        MQTT_USERNAME = "teslamate"
        #MQTT_PASSWORD = "7d6e01e42ea4a2d89a6b26a626d22065"
      }

      resources {
        cpu    = 500
        memory = 4196
      }
    }
  }
}
