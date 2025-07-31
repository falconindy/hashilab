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

      port "http" {
        to = 8096
      }
    }

    volume "media" {
      type            = "csi"
      read_only       = false
      source          = "media"
      access_mode     = "multi-node-multi-writer"
      attachment_mode = "file-system"
    }

    volume "jellyfin" {
      type            = "csi"
      read_only       = false
      source          = "jellyfin"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    task "jellyfin" {
      driver = "podman"

      config {
        image = "linuxserver/jellyfin:10.10.7"
        ports = ["http"]

        devices = [
          "/dev/dri",
        ]
      }

      env {
        PUID = 911
        PGID = 911
      }

      volume_mount {
        volume      = "jellyfin"
        destination = "/config"
        read_only   = false
      }

      volume_mount {
        volume      = "media"
        destination = "/media"
        read_only   = false
      }

      service {
        port         = "http"
        name         = "jellyfin"
        address_mode = "host"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.${NOMAD_JOB_NAME}.rule=Host(`${NOMAD_JOB_NAME}.service.home`)",
          "traefik.http.routers.${NOMAD_JOB_NAME}.entrypoints=http",
        ]
        check {
          type     = "http"
          path     = "/health"
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
