job "jackett" {
  datacenters = ["dc1"]
  type        = "service"

  group "jackett" {
    network {
      mode = "bridge"

      port "http" {
        to = 9117
      }
    }

    task "server" {
      driver = "podman"

      config {
        image = "lscr.io/linuxserver/jackett:0.24.521"
        ports = ["http"]

        volumes = [
          "/etc/ssl/certs:/etc/ssl/certs:ro",
          "/clusterdata/jackett:/config:rw",
        ]
      }

      env {
        PUID = "1000"
        PGID = "1000"
        TZ   = "America/New_York"
      }

      resources {
        cpu    = 200
        memory = 256
      }

      service {
        name         = "jackett"
        port         = "http"
        address_mode = "host"

        tags = [
          "traefik.enable=true",
        ]

        check {
          type     = "http"
          path     = "/health"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
