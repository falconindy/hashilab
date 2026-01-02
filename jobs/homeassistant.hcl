job "homeassistant" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "A plugin-driven DNS server/forwarder"
    link {
      label = "Upstream"
      url   = "https://home-assistant.io"
    }
    link {
      label = "GitHub"
      url   = "https://github.com/home-assistant/core"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/r/homeassistant/home-assistant"
    }
  }

  group "homeassistant" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "http" {}
    }

    task "server" {
      driver = "podman"
      config {
        image        = "homeassistant/home-assistant:2025.12.5"
        network_mode = "host"
        ports        = ["http"]
        volumes = [
          "/run/dbus:/run/dbus",
          "/etc/ssl/certs:/etc/ssl/certs:ro",
          "/clusterdata/homeassistant:/config:rw",
        ]
      }

      template {
        destination = "local/http.yaml"
        data        = <<-EOF
          server_port: {{ env "NOMAD_PORT_http" }}
          use_x_forwarded_for: true
          trusted_proxies:
            - 10.0.100.0/24
            - 172.16.0.0/12
        EOF
      }

      env {
        TZ                 = "America/New_York"
        REQUESTS_CA_BUNDLE = "/etc/ssl/certs/ca-certificates.crt"
        # ref: https://github.com/home-assistant/core/issues/155924
        GRPC_VERBOSITY = "NONE"
      }

      service {
        name    = "homeassistant"
        port    = "http"
        address = "l.service.home"

        check {
          type     = "http"
          path     = "/manifest.json"
          interval = "10s"
          timeout  = "2s"
        }
      }

      resources {
        cpu    = 500
        memory = 2048
      }
    }
  }
}
