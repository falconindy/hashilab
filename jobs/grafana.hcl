job "grafana" {
  datacenters = ["dc1"]
  type        = "service"

  group "grafana" {
    count = 1

    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "http" {
        to = 3000
      }
    }

    task "server" {
      driver = "podman"
      user   = "1000:1000"
      config {
        image  = "grafana/grafana:12.2.1"
        userns = "host"

        volumes = [
          "/etc/ssl/certs:/etc/ssl/certs:ro",
          "/clusterdata/grafana:/var/lib/grafana:rw",
        ]
      }

      env {
        GF_SERVER_ROOT_URL    = "https://grafana.service.home"
        GF_PATHS_DATA         = "/var/lib/grafana"
        GF_AUTH_BASIC_ENABLED = "false"
        GF_PLUGINS_PREINSTALL = "grafana-piechart-panel"

        GF_USERS_ALLOW_SIGN_UP = "false"
      }
      service {
        port         = "http"
        name         = "grafana"
        address_mode = "host"
        tags = [
          "traefik.enable=true",
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
