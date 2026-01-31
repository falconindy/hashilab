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
          "--watch-file=/certs/trust/pki.pem",
          "--watch-file=/certs/trust/pki_int.pem",
          "--watch-file=/certs/trust/pki_int_internal.pem",
          "--listen-address=:${NOMAD_HOST_PORT_metrics}",
        ]

        volumes = [
          "/etc/vault.d/client.crt:/certs/vault/client.crt:ro",
          "local/pki.pem:/certs/trust/pki.pem:ro",
          "local/pki_int.pem:/certs/trust/pki_int.pem:ro",
          "local/pki_int_internal.pem:/certs/trust/pki_int_internal.pem:ro",
        ]
      }

      artifact {
        source      = "http://172.17.0.1:8200/v1/pki/ca/pem"
        destination = "local/pki.pem"
        mode        = "file"
      }

      artifact {
        source      = "http://172.17.0.1:8200/v1/pki_int/ca/pem"
        destination = "local/pki_int.pem"
        mode        = "file"
      }

      artifact {
        source      = "http://172.17.0.1:8200/v1/pki_int_internal/ca/pem"
        destination = "local/pki_int_internal.pem"
        mode        = "file"
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }

    service {
      name         = "x509-exporter"
      port         = "metrics"
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
