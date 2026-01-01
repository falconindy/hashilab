job "esphome" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "A plugin-driven DNS server/forwarder"
    link {
      label = "Upstream"
      url   = "https://esphome.io"
    }
    link {
      label = "GitHub"
      url   = "https://github.com/esphome/esphome"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/r/esphome/esphome"
    }
  }

  group "esphome" {
    network {
      dns {
        servers = ["172.17.0.1"]
      }

      port "http" {
        static = 6052
      }
    }

    task "server" {
      driver = "podman"
      config {
        image        = "esphome/esphome:2025.12.4"
        network_mode = "host"
        ports        = ["http"]
        volumes = [
          "/clusterdata/esphome/cache:/cache:rw",
          "/clusterdata/esphome/config:/config:rw",
        ]
      }

      service {
        name    = "esphome"
        port    = "http"
        address = "l.service.home"

        check {
          type     = "http"
          path     = "/version"
          interval = "10s"
          timeout  = "2s"
        }
      }

      env {
        TZ = "America/New_York"
      }

      resources {
        cpu    = 500
        memory = 4096
      }
    }
  }
}
