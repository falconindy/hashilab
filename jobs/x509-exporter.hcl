job "x509-exporter" {
  datacenters = ["dc1"]
  type        = "system"

  group "x509-exporter" {
    constraint {
      attribute = "${meta.has_vault}"
      value     = "true"
    }

    network {
      mode = "bridge"

      port "metrics" {}
    }

    task "exporter" {
      driver = "podman"

      config {
        image = "enix/x509-certificate-exporter:3.19.1-alpine"
        ports = ["metrics"]

        args = [
          "--watch-file=/certs/vault/client.crt",
          "--listen-address=:${NOMAD_HOST_PORT_metrics}",
        ]

        volumes = [
          "/etc/vault.d:/certs/vault:ro"
        ]
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }

    service {
      name = "x509-exporter"
      port = "metrics"
      address_mode = "host"

      check {
        type     = "http"
        path     = "/metrics"
        interval = "10s"
        timeout  = "2s"
      }
    }
  }
}
