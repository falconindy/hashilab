job "omada-exporter" {
  datacenters = ["dc1"]
  type        = "service"

  group "omada-exporter" {
    network {
      port "metrics" {}
    }

    task "omada-exporter" {
      driver = "docker"

      config {
        image = "chhaley/omada_exporter:0.13.1"
        ports = ["metrics"]
      }

      service {
        name = "omada-exporter"
        port = "metrics"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.${NOMAD_JOB_NAME}.rule=Host(`${NOMAD_JOB_NAME}.service.home`)",
          "traefik.http.routers.${NOMAD_JOB_NAME}.entrypoints=http",
        ]

        check {
          type     = "http"
          path     = "/"
          name     = "http"
          interval = "5s"
          timeout  = "2s"
        }
      }

      env {
        OMADA_HOST = "https://10.0.1.100:10443"
        OMADA_USER = "prometheus"
        OMADA_SITE = "Default"
        OMADA_PORT = "${NOMAD_PORT_metrics}"
        OMADA_INSECURE = "true"
      }

      vault {}

      identity {
        name = "vault_default"
        aud  = ["vault.io"]
        ttl  = "1h"
      }

      template {
        data        = <<EOH
          {{ with secret "kv/data/default/omada-exporter" }}
            OMADA_PASS="{{ .Data.data.omada_password }}"
          {{ end }}
      EOH
        destination = "secrets/auth.env"
        env         = true
      }
    }
  }
}
