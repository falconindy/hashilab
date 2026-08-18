job "omada-exporter" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "Prometheus exporter for TP-Link Omada controller metrics"
    link {
      label = "GitHub"
      url   = "https://github.com/RCooLeR/omada_exporter"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/r/rcooler/omada_exporter"
    }
  }

  group "omada-exporter" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "omada_metrics" {}
      port "envoy_metrics" { to = 9102 }
    }

    task "server" {
      driver = "docker"
      user   = "1000:1000"

      config {
        image = "rcooler/omada_exporter:2.4.0"

        cap_drop     = ["all"]
        security_opt = ["no-new-privileges=true"]

        volumes = [
          "/etc/ssl/certs/ca-certificates.crt:/etc/ssl/certs/ca-certificates.crt:ro",
        ]
      }

      env {
        LOG_LEVEL = "warn"

        OMADA_HOST = "https://omada-controller.service.home:8043"
        OMADA_USER = "exporter"
        OMADA_PORT = "9202"
      }

      vault {}

      template {
        data        = <<-EOF
          {{ with (secret "kv/data/default/omada-exporter").Data.data }}
            OMADA_PASS="{{ .omada_password }}"
            OMADA_CLIENT_ID="{{ .openapi_client_id }}"
            OMADA_SECRET_ID="{{ .openapi_secret_id }}"
          {{ end }}
        EOF
        destination = "secrets/env"
        env         = true
      }
    }

    service {
      name = "omada-exporter"
      port = 9202

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}"
        omada_metrics_port = "${NOMAD_HOST_PORT_omada_metrics}"
      }

      connect {
        sidecar_service {
          proxy {
            transparent_proxy {
              no_dns = true
            }

            expose {
              path {
                path            = "/metrics"
                protocol        = "http"
                local_path_port = 9102
                listener_port   = "envoy_metrics"
              }
              path {
                path            = "/metrics"
                protocol        = "http"
                local_path_port = 9202
                listener_port   = "omada_metrics"
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
        path     = "/healthz"
        name     = "http"
        interval = "5s"
        timeout  = "2s"
        expose   = true
      }
    }
  }
}
