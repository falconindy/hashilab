job "mqtt-explorer" {
  datacenters = ["dc1"]
  type        = "service"

  group "mqtt-explorer" {
    count = 1

    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "http" {}
    }

    volume "mqtt-explorer" {
      type            = "csi"
      read_only       = false
      source          = "mqtt-explorer"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    task "mqtt-explorer" {
      driver = "podman"

      config {
        image = "smeagolworms4/mqtt-explorer:browser-1.0.3"
      }

      service {
        name         = "mqtt-explorer"
        port         = "http"
        address_mode = "host"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.${NOMAD_JOB_NAME}.rule=Host(`${NOMAD_JOB_NAME}.service.home`)",
          "traefik.http.routers.${NOMAD_JOB_NAME}.entrypoints=http",
        ]
      }

      env {
        HTTP_PORT = "${NOMAD_PORT_http}"
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
