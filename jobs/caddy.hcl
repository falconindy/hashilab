job "caddy" {
  datacenters = ["dc1"]
  type        = "system"

  update {
    max_parallel     = 1
    min_healthy_time = "10s"
    auto_revert      = true
  }

  group "caddy" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "public" {
        static = 8443
      }

      port "admin" {
        static = 2019
      }
    }

    task "server" {
      driver = "podman"

      config {
        image        = "docker-registry.service.home/falconindy/caddy:latest"
        ports        = ["admin", "public"]
        network_mode = "host"

        args = [
          "caddy", "run",
          "--config", "/etc/caddy/Caddyfile",
          "--adapter", "caddyfile",
        ]

        volumes = [
          "/etc/ssl/certs:/etc/ssl/certs:ro",
          "/clusterdata/caddy/config:/etc/caddy:ro",
          "/clusterdata/www:/static:ro",
        ]
      }

      vault {}

      template {
        data        = <<EOF
          {{ with secret "kv/data/default/caddy" }}
            CF_DNS_API_TOKEN="{{ .Data.data.cloudflare_api_token }}"
          {{ end }}
        EOF
        destination = "secrets/cloudflare.env"
        env         = true
      }

      env {
        CADDY_ADMIN = "0.0.0.0:${NOMAD_PORT_admin}"
      }

      resources {
        cpu    = 100
        memory = 256
      }
    }

    service {
      name         = "caddy-https"
      port         = 443
      address_mode = "host"

      connect {
        sidecar_service {}

        sidecar_task {
          resources {
            cpu    = 50
            memory = 48
          }
        }
      }
    }

    service {
      name         = "caddy-http"
      port         = 80
      address_mode = "host"

      connect {
        sidecar_service {}

        sidecar_task {
          resources {
            cpu    = 50
            memory = 48
          }
        }
      }
    }

    service {
      name         = "caddy"
      port         = "admin"
      address_mode = "host"

      check {
        type     = "http"
        path     = "/config/"
        interval = "10s"
        timeout  = "2s"
      }
    }
  }
}
