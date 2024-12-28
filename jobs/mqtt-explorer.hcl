job "mqtt-explorer" {
  datacenters = ["dc1"]
  type        = "service"

  group "mqtt-explorer" {
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

    volume "mqtt-explorer" {
      type            = "csi"
      read_only       = false
      source          = "mqtt-explorer"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    task "mqtt-explorer" {
      driver = "docker"

      config {
        image = "smeagolworms4/mqtt-explorer:browser-1.0.3"
      }

      service {
        name = "mqtt-explorer"
        port = "http"
      }

      volume_mount {
        volume      = "mqtt-explorer"
        destination = "/mqtt-explorer/config"
        read_only   = false
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
