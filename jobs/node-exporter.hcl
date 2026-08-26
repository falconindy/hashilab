job "node-exporter" {
  datacenters = ["*"]
  type        = "system"

  ui {
    description = "Prometheus exporter for hardware and OS metrics exposed by *NIX kernels"
    link {
      label = "Upstream"
      url   = "https://prometheus.io"
    }
    link {
      label = "GitHub"
      url   = "https://github.com/prometheus/node_exporter"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/r/prom/node-exporter"
    }
  }

  group "node-exporter" {
    network {
      port "metrics" {}
    }

    task "server" {
      driver = "docker"

      config {
        image = "prom/node-exporter:v1.12.1"
        ports = ["metrics"]

        # Necessary to see the host's real processes and network
        network_mode = "host"
        pid_mode     = "host"

        cap_drop     = ["all"]
        security_opt = ["no-new-privileges=true"]

        args = [
          "--web.listen-address=:${NOMAD_PORT_metrics}",
          "--path.rootfs=/host",
          "--collector.filesystem.mount-points-exclude=^/(dev|proc|sys|var/lib/docker/.+)($|/)"
        ]

        # Mount the host filesystem so node_exporter can "see" outside the container
        mount {
          type     = "bind"
          source   = "/"
          target   = "/host"
          readonly = true

          bind_options {
            propagation = "rslave"
          }
        }
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }

    service {
      name = "node-exporter"
      port = "metrics"

      check {
        name     = "alive"
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }
    }
  }
}
