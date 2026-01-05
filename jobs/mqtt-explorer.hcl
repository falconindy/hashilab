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

      env {
        HTTP_PORT = "${NOMAD_PORT_http}"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }

    service {
      name = "mqtt-explorer"
      port = "http"

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }
    }
  }
}
