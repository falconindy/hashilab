job "victorialogs" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "Fast, cost-effective and easy to use log database"
    link {
      label = "Upstream"
      url   = "https://docs.victoriametrics.com/victorialogs/"
    }
    link {
      label = "GitHub"
      url   = "https://github.com/VictoriaMetrics/VictoriaMetrics"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/r/victoriametrics/victoria-logs"
    }
  }

  group "victorialogs" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "vl_metrics" {}
      port "envoy_metrics" { to = 9102 }
    }

    task "server" {
      driver = "docker"
      user   = "1000:1000"

      config {
        image = "victoriametrics/victoria-logs:v1.51.0"
        args = [
          "-storageDataPath=/victoria-logs-data",
          "-retentionPeriod=90d",
          "-httpListenAddr=:9428",
        ]
        volumes = [
          "/clusterdata/victorialogs:/victoria-logs-data:rw",
        ]
      }

      resources {
        cpu    = 150
        memory = 192
      }
    }

    service {
      name = "victorialogs"
      port = 9428

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}"
        vl_metrics_port    = "${NOMAD_HOST_PORT_vl_metrics}"
      }

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=true",
      ]

      connect {
        sidecar_service {
          proxy {
            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9102"
            }

            expose {
              path {
                path            = "/metrics"
                protocol        = "http"
                local_path_port = 9428
                listener_port   = "vl_metrics"
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
        path     = "/health"
        name     = "http"
        interval = "10s"
        timeout  = "2s"
        expose   = true
      }
    }
  }
}
