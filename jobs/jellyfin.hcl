job "jellyfin" {
  datacenters = ["dc1"]
  type        = "service"

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

    volume "jellyfin-config" {
      type            = "csi"
      read_only       = false
      source          = "jellyfin-config"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    volume "jellyfin-cache" {
      type            = "csi"
      read_only       = false
      source          = "jellyfin-cache"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    task "jellyfin" {
      driver = "docker"

      config {
        image = "jellyfin/jellyfin:2025010605"
        ports = ["http"]

        devices = [
          {
            host_path          = "/dev/dri"
            container_path     = "/dev/dri"
            cgroup_permissions = "rw"
          }
        ]
      }

      volume_mount {
        volume      = "jellyfin-config"
        destination = "/config"
        read_only   = false
      }

      volume_mount {
        volume      = "jellyfin-cache"
        destination = "/cache"
        read_only   = false
      }

      volume_mount {
        volume      = "media"
        destination = "/media"
        read_only   = false
      }

      service {
        port = "http"
        name = "jellyfin"
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
