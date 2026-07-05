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

      port "metrics" {}
    }

    task "server" {
      driver = "docker"
      user   = "1000:1000"

      config {
        image = "rcooler/omada_exporter:2.3.0"
        ports = ["metrics"]

        cap_drop     = ["all"]
        security_opt = ["no-new-privileges=true"]

        volumes = [
          "/etc/ssl/certs/ca-certificates.crt:/etc/ssl/certs/ca-certificates.crt:ro",
        ]
      }

      env {
        OMADA_HOST = "https://omada-controller.service.home:8043"
        OMADA_USER = "exporter"
        OMADA_PORT = "${NOMAD_PORT_metrics}"
      }

      vault {}

      template {
        data        = <<EOF
          {{ with secret "kv/data/default/omada-exporter" }}
            OMADA_PASS="{{ .Data.data.omada_password }}"
            OMADA_CLIENT_ID="{{ .Data.data.openapi_client_id }}"
            OMADA_SECRET_ID="{{ .Data.data.openapi_secret_id }}"
          {{ end }}
        EOF
        destination = "secrets/auth.env"
        env         = true
      }
    }

    service {
      name = "omada-exporter"
      port = "metrics"

      check {
        type     = "http"
        path     = "/healthz"
        name     = "http"
        interval = "5s"
        timeout  = "2s"
      }
    }
  }
}
