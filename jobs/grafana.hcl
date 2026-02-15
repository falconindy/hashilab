job "grafana" {
  datacenters = ["dc1"]
  type        = "service"

  group "grafana" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "envoy_metrics" { to = 9102 }
    }

    task "server" {
      driver = "docker"
      user   = "1000:1000"
      config {
        image       = "grafana/grafana:12.3.3"
        userns_mode = "host"

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

      resources {
        cpu    = 100
        memory = 128
      }
    }

    service {
      name = "grafana"
      port = 3000

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=true",
      ]

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}"
      }

      connect {
        sidecar_service {
          proxy {
            transparent_proxy {
              no_dns = true
            }

            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9102"
            }

            expose {
              path {
                path            = "/metrics"
                protocol        = "http"
                local_path_port = 9102
                listener_port   = "envoy_metrics"
              }
            }
          }
        }

        sidecar_task {
          resources {
            cpu    = 50
            memory = 48
          }
        }
      }

      check {
        type     = "http"
        path     = "/api/health"
        interval = "10s"
        timeout  = "2s"
        expose   = true
      }
    }
  }
}
