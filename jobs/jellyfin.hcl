job "jellyfin" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${meta.has_quicksync}"
    operator  = "="
    value     = "true"
  }

  group "jellyfin" {
    count = 1

    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "http" {
        to = 8096
      }

      port "discovery" {
        static = 7359
      }
    }

    task "server" {
      driver = "podman"

      config {
        image = "jellyfin/jellyfin:10.11.5"
        ports = ["http", "discovery"]

        volumes = [
          "/etc/ssl/certs:/etc/ssl/certs:ro",
          "/clusterdata/jellyfin:/config:rw",
          "/clusterdata/media:/media:rw",
        ]

        devices = [
          "/dev/dri",
        ]
      }

      env {
        JELLYFIN_PublishedServerUrl = "https://jellyfin.service.home"
        PUID                        = 911
        PGID                        = 911
      }

      resources {
        cpu    = 500
        memory = 4096
      }
    }

    service {
      name         = "jellyfin"
      port         = "http"
      address_mode = "host"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.${NOMAD_JOB_NAME}.entrypoints=https,http",
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
