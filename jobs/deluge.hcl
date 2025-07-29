job "deluge" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${attr.unique.network.ip-address}"
    operator  = "="
    value     = "10.0.100.102"
  }

  group "deluge" {
    count = 1

    network {
      mode = "bridge"

      port "deluge" {
        to = 8112
      }

      port "deluge-inbound" {
        static = 6881
      }
    }

    volume "media" {
      type            = "csi"
      read_only       = false
      source          = "media"
      access_mode     = "multi-node-multi-writer"
      attachment_mode = "file-system"
    }

    volume "deluge-config" {
      type            = "csi"
      read_only       = false
      source          = "deluge-config"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }


    task "deluge" {
      driver = "podman"

      config {
        image = "linuxserver/deluge:amd64-2.2.0"
        ports = ["deluge", "deluge-inbound"]
      }

      volume_mount {
        volume      = "media"
        destination = "/media"
        read_only   = false
      }

      volume_mount {
        volume      = "deluge-config"
        destination = "/config"
        read_only   = false
      }

      env {
        PUID = 911
        PGID = 911
      }

      service {
        name = "deluge"
        port = "deluge"
        address_mode = "host"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.${NOMAD_TASK_NAME}.rule=Host(`${NOMAD_TASK_NAME}.service.home`)",
          "traefik.http.routers.${NOMAD_TASK_NAME}.entrypoints=http",
        ]
        check {
          type     = "http"
          path     = "/"
          interval = "10s"
          timeout  = "5s"
        }
      }

      resources {
        cpu    = 200
        memory = 1024
      }
    }
  }
}
