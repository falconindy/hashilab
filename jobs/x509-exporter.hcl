job "x509-exporter" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "A Prometheus exporter to monitor x509 certificate expiry"
    link {
      label = "GitHub"
      url   = "https://github.com/enix/x509-certificate-exporter"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/r/enix/x509-certificate-exporter"
    }
  }

  # Only watches the PKI mounts' CA certs, which it fetches from Vault itself
  # -- nothing host-local -- so one instance covers the whole cluster. Vault's
  # own server cert is probed by blackbox instead (jobs/monitoring.hcl's
  # tls-expiration job).
  group "x509-exporter" {
    count = 1

    network {
      mode = "bridge"

      port "metrics" {}
    }

    task "exporter" {
      driver = "docker"
      # Templates render 0644, so nothing it reads needs root.
      user = "nobody"

      config {
        image = "enix/x509-certificate-exporter:3.21.0-alpine"
        ports = ["metrics"]

        cap_drop     = ["all"]
        security_opt = ["no-new-privileges=true"]

        args = [
          "--watch-dir=/certs/trust",
          "--listen-address=:${NOMAD_HOST_PORT_metrics}",
        ]

        volumes = [
          "local/pki.pem:/certs/trust/pki.pem:ro",
          "local/pki_int.pem:/certs/trust/pki_int.pem:ro",
          "local/pki_int_internal.pem:/certs/trust/pki_int_internal.pem:ro",
          "local/pki_int_connect.pem:/certs/trust/pki_int_connect.pem:ro",
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

      # pki_int_connect's intermediate is generated and rotated by Consul, not
      # tofu, but the mount's cert/ca read is unauthenticated (built into the
      # PKI secrets engine) same as the other three, so it needs no extra
      # Vault policy grant.
      template {
        data        = <<-EOF
          {{- with secret "pki_int_connect/cert/ca" }}
            {{- .Data.certificate }}
          {{ end }}
        EOF
        destination = "local/pki_int_connect.pem"
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
