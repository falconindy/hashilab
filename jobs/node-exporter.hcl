job "node-exporter" {
  datacenters = ["*"]
  type        = "system"

  group "node-exporter" {
    network {
      port "metrics" {
        static = 9100
      }
    }

    task "server" {
      driver = "docker"

      config {
        image = "prom/node-exporter:v1.11.0"
        ports = ["metrics"]

        # Necessary to see the host's real processes and network
        network_mode = "host"
        pid_mode     = "host"

        args = [
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
