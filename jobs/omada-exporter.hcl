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
      }

      service {
        name         = "omada-exporter"
        port         = "metrics"
        address_mode = "host"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.${NOMAD_JOB_NAME}.rule=Host(`${NOMAD_JOB_NAME}.service.home`)",
          "traefik.http.routers.${NOMAD_JOB_NAME}.entrypoints=https",
          "traefik.http.routers.${NOMAD_JOB_NAME}.tls.certresolver=vault",
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
        OMADA_HOST     = "https://10.0.1.99:8043"
        OMADA_USER     = "prometheus"
        OMADA_SITE     = "Default"
        OMADA_PORT     = "${NOMAD_PORT_metrics}"
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
