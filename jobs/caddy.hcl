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

      port "http" {
        static = 80
      }
      port "https" {
        static = 443
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
        ports        = ["admin", "http", "https", "public"]
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

      service {
        name         = "l"
        port         = "https"
        address_mode = "host"
      }

      service {
        name         = "caddy"
        port         = "admin"
        address_mode = "host"

        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
