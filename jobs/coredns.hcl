job "coredns" {
  datacenters = ["dc1"]
  type        = "system"

  group "coredns" {
    count = 1

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
    }

    task "server" {
      driver = "podman"
      config {
        image        = "coredns/coredns:1.13.0"
        network_mode = "host"
        ports        = ["dns", "metrics"]
        args         = ["-conf", "/local/coredns/corefile"]
      }

      service {
        port         = "dns"
        name         = "coredns"
        address_mode = "host"
        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }

      template {
        data            = <<EOH
. {
  bind {{ env "NOMAD_IP_dns" }}
  forward . 8.8.8.8 8.8.4.4
  cache {
    serve_stale 24h
    prefetch 10 1m 20%
  }
  whoami
  errors
  prometheus {{ env "NOMAD_IP_metrics" }}:9153
}
home.:53 consul.:53 {
  bind {{ env "NOMAD_IP_dns" }}
  forward . {{ env "NOMAD_HOST_IP_metrics" }}:8600
  whoami
  errors
  prometheus {{ env "NOMAD_IP_metrics" }}:9153
}
EOH
        destination     = "local/coredns/corefile"
        env             = false
        change_mode     = "signal"
        change_signal   = "SIGHUP"
        left_delimiter  = "{{"
        right_delimiter = "}}"
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
