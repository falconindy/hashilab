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
      driver = "docker"
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
        memory = 128
      }

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }
    }

    task "server" {
      driver = "docker"
      user   = "1000:1000"
      config {
        image       = "grafana/grafana:11.4.0"
        userns_mode = "host"
      }
      volume_mount {
        volume      = "grafana"
        destination = "/var/lib/grafana"
        read_only   = false
      }
      env {
        GF_SERVER_ROOT_URL    = "https://grafana.falconindy.com"
        GF_PATHS_DATA         = "/var/lib/grafana"
        GF_AUTH_BASIC_ENABLED = "false"
        GF_INSTALL_PLUGINS    = "grafana-piechart-panel"

        GF_USERS_ALLOW_SIGN_UP = "false"
      }
      service {
        port = "http"
        name = "grafana"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.${NOMAD_JOB_NAME}.rule=Host(`${NOMAD_JOB_NAME}.falconindy.com`)",
          "traefik.http.routers.${NOMAD_JOB_NAME}.entrypoints=https",
          "traefik.http.routers.${NOMAD_JOB_NAME}.tls.certresolver=letsEncrypt",
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

