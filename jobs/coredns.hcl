job "coredns" {
  datacenters = ["dc1"]
  type        = "system"

  update {
    max_parallel     = 1
    min_healthy_time = "10s"
    auto_revert      = true
  }

  ui {
    description = "A plugin-driven DNS server/forwarder"
    link {
      label = "Upstream"
      url   = "https://coredns.io"
    }
    link {
      label = "GitHub"
      url   = "https://github.com/coredns/coredns"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/r/coredns/coredns"
    }
  }

  group "coredns" {
    network {
      mode = "host"

      dns {
        servers = ["172.17.0.1"]
      }

      port "dns" {
        static = 53
      }
      port "metrics" {
        static = 9153
      }
      port "health" {}
    }

    task "server" {
      driver = "podman"
      config {
        image        = "coredns/coredns:1.13.2"
        network_mode = "host"
        ports        = ["dns", "metrics", "health"]
        args         = ["-conf", "/local/corefile"]
      }

      service {
        name         = "coredns"
        port         = "health"
        address_mode = "host"

        check {
          type     = "http"
          path     = "/health"
          interval = "10s"
          timeout  = "2s"
        }
      }

      template {
        data            = <<-EOF
          . {
            bind {$NOMAD_IP_dns}
            health :{$NOMAD_PORT_health}
            prometheus {$NOMAD_ADDR_metrics}

            errors

            cache {
              serve_stale 24h
              prefetch 10 1m 20%
            }

            forward home {$NOMAD_HOST_IP_metrics}:8600
            forward consul {$NOMAD_HOST_IP_metrics}:8600
            forward . 8.8.8.8 8.8.4.4
          }
        EOF
        destination     = "local/corefile"
        env             = false
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
