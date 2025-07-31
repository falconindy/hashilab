job "grafana" {
  datacenters = ["dc1"]
  type        = "service"

  group "grafana" {
    count = 1

    network {
      mode = "bridge"
      port "http" {
        to = 3000
      }
    }

    volume "grafana" {
      type            = "csi"
      read_only       = false
      source          = "grafana"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    task "prep-disk" {
      driver = "podman"
      volume_mount {
        volume      = "grafana"
        destination = "/volume/"
        read_only   = false
      }
      config {
        image   = "busybox:latest"
        command = "sh"
        args    = ["-c", "chown -R 1000:1000 /volume/"]
      }
      resources {
        cpu    = 100
        memory = 512
      }

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }
    }

    task "server" {
      driver = "podman"
      user   = "1000:1000"
      config {
        image       = "grafana/grafana:12.1.0"
        userns = "host"
      }
      volume_mount {
        volume      = "grafana"
        destination = "/var/lib/grafana"
        read_only   = false
      }
      env {
        GF_SERVER_ROOT_URL    = "https://grafana.service.home"
        GF_PATHS_DATA         = "/var/lib/grafana"
        GF_AUTH_BASIC_ENABLED = "false"
        GF_INSTALL_PLUGINS    = "grafana-piechart-panel"

        GF_USERS_ALLOW_SIGN_UP = "false"
      }
      service {
        port = "http"
        name = "grafana"
        address_mode = "host"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.${NOMAD_JOB_NAME}.rule=Host(`${NOMAD_JOB_NAME}.service.home`)",
          "traefik.http.routers.${NOMAD_JOB_NAME}.entrypoints=https",
          "traefik.http.routers.${NOMAD_JOB_NAME}.tls.certresolver=vault",
        ]
        check {
          type     = "http"
          path     = "/api/health"
          interval = "10s"
          timeout  = "2s"
        }
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
