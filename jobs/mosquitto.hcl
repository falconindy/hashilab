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
      port "mqtt" {
        static = 1883
      }
    }

    task "mosquitto" {
      driver = "docker"
      config {
        image      = "eclipse-mosquitto:2.0.20"
        privileged = true
        ports      = ["mqtt"]
      }

      volume_mount {
        volume      = "mosquitto"
        destination = "/mosquitto"
        read_only   = false
      }

      service {
        name = "mosquitto"
        port = "mqtt"
      }

      env {
        TZ = "America/New_York"
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
