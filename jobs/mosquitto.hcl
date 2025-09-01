job "mosquitto" {
  datacenters = ["dc1"]
  type        = "service"

  group "mosquitto" {
    count = 1

    volume "mosquitto" {
      type            = "csi"
      read_only       = false
      source          = "mosquitto"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

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
      }

      volume_mount {
        volume      = "mosquitto"
        destination = "/mosquitto"
        read_only   = false
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
