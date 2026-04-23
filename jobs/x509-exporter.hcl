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
      driver = "docker"

      config {
        image = "enix/x509-certificate-exporter:3.21.0-alpine"
        ports = ["metrics"]

        args = [
          "--watch-dir=/certs/vault",
          "--watch-dir=/certs/trust",
          "--listen-address=:${NOMAD_HOST_PORT_metrics}",
        ]

        volumes = [
          "/etc/vault.d/client.crt:/certs/vault/client.crt:ro",
          "local/pki.pem:/certs/trust/pki.pem:ro",
          "local/pki_int.pem:/certs/trust/pki_int.pem:ro",
          "local/pki_int_internal.pem:/certs/trust/pki_int_internal.pem:ro",
        ]
      }

      vault {}

      template {
        data        = <<-EOF
          {{- with secret "pki/cert/ca" }}
            {{- .Data.certificate }}
          {{ end }}
        EOF
        destination = "local/pki.pem"
      }

      template {
        data        = <<-EOF
          {{- with secret "pki_int/cert/ca" }}
            {{- .Data.certificate }}
          {{ end }}
        EOF
        destination = "local/pki_int.pem"
      }

      template {
        data        = <<-EOF
          {{- with secret "pki_int_internal/cert/ca" }}
            {{- .Data.certificate }}
          {{ end }}
        EOF
        destination = "local/pki_int_internal.pem"
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }

    service {
      name = "x509-exporter"
      port = "metrics"

      check {
        type     = "http"
        path     = "/metrics"
        interval = "10s"
        timeout  = "2s"
      }
    }
  }
}
