job "esphome" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "A framework for creating firmware for popular microcontrollers"
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
      driver = "docker"
      config {
        image        = "esphome/esphome:2026.4.3"
        network_mode = "host"
        ports        = ["http"]
        volumes = [
          "/clusterdata/esphome/cache:/cache:rw",
          "/clusterdata/esphome/config:/config:rw",
        ]
      }

      env {
        TZ = "America/New_York"
      }

      resources {
        cpu    = 500
        memory = 4096
      }
    }

    service {
      name = "esphome"
      port = "http"

      tags = [
        "traefik.enable=true",
      ]

      check {
        type     = "http"
        path     = "/version"
        interval = "10s"
        timeout  = "2s"
      }
    }
  }
}
