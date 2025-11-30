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

    task "server" {
      driver = "podman"

      config {
        image = "smeagolworms4/mqtt-explorer:browser-1.0.3"
        volumes = [
          "/clusterdata/mqtt-explorer:/mqtt-explorer/config:rw"
        ]
      }

      service {
        name         = "mqtt-explorer"
        port         = "http"
        address_mode = "host"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.${NOMAD_JOB_NAME}.entrypoints=https",
        ]
      }

      env {
        HTTP_PORT = "${NOMAD_PORT_http}"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
