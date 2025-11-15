job "esphome" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "A plugin-driven DNS server/forwarder"
    link {
      label = "Upstream"
      url = "https://esphome.io"
    }
    link {
      label = "GitHub"
      url = "https://github.com/esphome/esphome"
    }
    link {
      label = "Docker Hub"
      url = "https://hub.docker.com/r/esphome/esphome"
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
        image        = "esphome/esphome:2025.9.3"
        network_mode = "host"
        ports        = ["http"]
        volumes = [
          "/etc/localtime:/etc/localtime:ro",
          "/clusterdata/esphome/cache:/cache:rw",
          "/clusterdata/esphome/config:/config:rw",
        ]
      }

      service {
        port         = "http"
        name         = "esphome"
        address_mode = "host"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.${NOMAD_JOB_NAME}.entrypoints=http",
          "traefik.http.routers.${NOMAD_JOB_NAME}-https.entrypoints=https",
          "traefik.http.routers.${NOMAD_JOB_NAME}-https.tls.certresolver=vault",
        ]

        check {
          type     = "http"
          path     = "/version"
          interval = "10s"
          timeout  = "2s"
        }
      }

      resources {
        cpu    = 500
        memory = 4096
      }
    }
  }
}
