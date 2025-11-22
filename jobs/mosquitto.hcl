job "mosquitto" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "A message broker that implements the MQTT protocol"
    link {
      label = "Upstream"
      url   = "https://mosquitto.org"
    }
    link {
      label = "GitHub"
      url   = "https://github.com/eclipse-mosquitto/mosquitto"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/_/eclipse-mosquitto"
    }
  }

  group "mosquitto" {
    count = 1

    network {
      dns {
        servers = ["172.17.0.1"]
      }

      port "mqtt" {
        static = 1883
      }
    }

    task "server" {
      driver = "podman"
      config {
        image        = "eclipse-mosquitto:2.0.22"
        network_mode = "host"
        ports        = ["mqtt"]

        volumes = [
          "/clusterdata/mosquitto:/mosquitto:rw",
        ]
      }

      service {
        name         = "mosquitto"
        port         = "mqtt"
        address_mode = "host"

        check {
          type     = "tcp"
          port     = "mqtt"
          interval = "30s"
          timeout  = "2s"
        }
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
