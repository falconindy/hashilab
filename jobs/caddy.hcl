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
          "--config", "/local/Caddyfile",
          "--adapter", "caddyfile",
        ]

        volumes = [
          "/etc/ssl/certs:/etc/ssl/certs:ro",
          "/clusterdata/caddy/${attr.unique.hostname}:/data:rw",
        ]
      }

      vault {}

      template {
        data        = <<-EOH
          {
              email d@falconindy.com
              http_port {{ env "NOMAD_PORT_http" }}
              https_port {{ env "NOMAD_PORT_https" }}

              on_demand_tls {
                ask http://localhost:9123/tls-check
              }

              storage redis {
                address valkey.service.home:6379
              }

              metrics {
                per_host
              }

              debug
          }


          http://localhost:9123 {
            @service_home expression `{query.domain}.endsWith(".service.home")`

            route /tls-check {
              respond @service_home "OK" 200
            }

            route * {
              abort
            }
          }

          (acme-service-home) {
            tls {
              ca https://vault.service.home:8200/v1/pki_int/acme/directory
              on_demand
            }
          }

          (acme-falconindy-com) {
            tls {
              ca https://acme-v02.api.letsencrypt.org/directory
              dns cloudflare {env.CF_DNS_API_TOKEN}
            }
          }

          (rproxy-via-srv) {
            reverse_proxy {
              dynamic srv {
                name {args[0]}
              }
            }
          }

          http://jellyfin.service.home {
            import rproxy-via-srv {host}
          }

          http://esphome.service.home {
            import rproxy-via-srv {host}
          }

          https://hass.falconindy.com:8443 {
            import acme-falconindy-com
            import rproxy-via-srv homeassistant.service.home
          }

          https:// {
            import acme-service-home
            import rproxy-via-srv {host}
          }
        EOH
        destination = "local/Caddyfile"
      }

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
        cpu    = 200
        memory = 256
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
