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

      env {
        ENCRYPTION_KEY = "${var.teslamate_encryption_key}"

        DATABASE_USER = "postgres"
        DATABASE_PASS = "${var.postgres_password}"
        DATABASE_NAME = "teslamate"
        DATABASE_HOST = "postgres.service.consul"

        MQTT_HOST     = "mosquitto.service.consul"
        MQTT_USERNAME = "teslamate"
        MQTT_PASSWORD = "${var.teslamate_mqtt_password}"
      }

      resources {
        cpu    = 500
        memory = 4196
      }
    }
  }
}

variable postgres_password {
  type = string
}

variable teslamate_encryption_key {
  type = string
}

variable teslamate_mqtt_password {
  type = string
}
