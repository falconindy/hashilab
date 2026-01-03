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

    task "omada-exporter" {
      driver = "podman"

      config {
        image = "chhaley/omada_exporter:0.13.1"
        ports = ["metrics"]

        volumes = [
          "/etc/ssl/certs:/etc/ssl/certs:ro",
        ]
      }

      service {
        name         = "omada-exporter"
        port         = "metrics"
        address_mode = "host"

        check {
          type     = "http"
          path     = "/"
          name     = "http"
          interval = "5s"
          timeout  = "2s"
        }
      }

      env {
        OMADA_HOST = "https://10.0.1.99:8043"
        OMADA_USER = "prometheus"
        OMADA_SITE = "Default"
        OMADA_PORT = "${NOMAD_PORT_metrics}"
      }

      vault {}

      template {
        data        = <<EOF
          {{ with secret "kv/data/default/omada-exporter" }}
            OMADA_PASS="{{ .Data.data.omada_password }}"
          {{ end }}
        EOF
        destination = "secrets/auth.env"
        env         = true
      }
    }
  }
}
