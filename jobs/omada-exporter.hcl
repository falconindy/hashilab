job "omada-exporter" {
  datacenters = ["dc1"]
  type        = "service"

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

      config {
        image = "rcooler/omada_exporter:2.2.1"
        ports = ["metrics"]

        volumes = [
          "/etc/ssl/certs:/etc/ssl/certs:ro",
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
