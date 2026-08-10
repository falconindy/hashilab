job "pocket-id" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "A simple and easy-to-use OIDC provider that allows users to authenticate with passkeys"
    link {
      label = "Upstream"
      url   = "https://pocket-id.org"
    }
    link {
      label = "GitHub"
      url   = "https://github.com/pocket-id/pocket-id"
    }
    link {
      label = "Container Image"
      url   = "https://github.com/pocket-id/pocket-id/pkgs/container/pocket-id"
    }
  }

  group "pocket-id" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "envoy_metrics" { to = 9102 }
    }

    ephemeral_disk {
      # Storage for GeoLite2-City.mmdb.
      size    = 300 # MB
      migrate = true
    }

    task "server" {
      driver = "docker"

      config {
        image = "ghcr.io/pocket-id/pocket-id:v2.13.0"

        volumes = [
          "/clusterdata/pocket-id:/app/data:rw",
        ]
      }

      env {
        TZ              = "America/New_York"
        APP_URL         = "https://id.falconindy.com"
        TRUST_PROXY     = "true"
        GEOLITE_DB_PATH = "/alloc/data/GeoLite2-City.mmdb"
      }

      vault {}

      template {
        data        = <<-EOF
          {{ with (secret "kv/data/default/pocket-id").Data.data }}
            ENCRYPTION_KEY="{{ .encryption_key }}"
            DB_CONNECTION_STRING="postgres://pocketid:{{ .postgres_password }}@postgres.virtual.home:80/pocketid?sslmode=disable"
            MAXMIND_LICENSE_KEY="{{ .maxmind_license_key }}"
          {{ end }}
        EOF
        destination = "secrets/env"
        env         = true
      }

      resources {
        cpu    = 100
        memory = 256
      }
    }

    service {
      name = "pocket-id"
      port = 1411

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}"
      }

      tags = [
        "traefik-ingress.enable=true",
        "traefik-ingress.http.routers.${NOMAD_JOB_NAME}.rule=Host(`id.falconindy.com`)",
      ]

      connect {
        sidecar_service {
          proxy {
            transparent_proxy {
              no_dns = true
            }

            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9102"
            }

            expose {
              path {
                path            = "/metrics"
                protocol        = "http"
                local_path_port = 9102
                listener_port   = "envoy_metrics"
              }
            }
          }
        }

        sidecar_task {
          resources {
            cpu    = 50
            memory = 48
          }
        }
      }

      check {
        type     = "http"
        path     = "/healthz"
        interval = "10s"
        timeout  = "2s"
        expose   = true
      }
    }
  }
}
