job "stirling" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "A locally hosted web application for performing operations on PDFs"
    link {
      label = "Upstream"
      url   = "https://www.stirlingpdf.com"
    }
    link {
      label = "GitHub"
      url   = "https://github.com/Stirling-Tools/Stirling-PDF"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/r/stirlingtools/stirling-pdf"
    }
  }

  group "stirling" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "envoy_metrics" { to = 9102 }
    }

    task "server" {
      driver = "docker"

      config {
        image = "stirlingtools/stirling-pdf:2.14.3-ultra-lite"
        volumes = [
          "/clusterdata/stirling/tessdata:/usr/share/tessdata:rw",
          "/clusterdata/stirling/configs:/configs:rw",
          "/clusterdata/stirling/customfiles:/customfiles:rw",
          "/clusterdata/stirling/logs:/logs:rw",
          "/clusterdata/stirling/pipeline:/pipeline:rw",
        ]
      }

      env {
        TZ = "America/New_York"
      }

      resources {
        cpu    = 100
        memory = 512
      }
    }

    service {
      name = "stirling"
      port = 8080

      tags = [
        "traefik.enable=true",
      ]

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}"
      }

      connect {
        sidecar_service {
          proxy {
            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9102"
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
        path     = "/api/v1/info/status"
        interval = "10s"
        timeout  = "2s"
        expose   = true
      }
    }
  }
}
