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

    task "server" {
      driver = "docker"

      config {
        image = "ghcr.io/pocket-id/pocket-id:v1.16.0"

        volumes = [
          "/clusterdata/pocket-id:/app/data:rw",
        ]
      }

      env {
        TZ = "America/New_York"

        # The canonical, externally-resolvable URL. This is the OIDC issuer
        # AND the WebAuthn RP ID, so it must be a single stable hostname that
        # every client (LAN and remote, browser and mobile) reaches it by.
        APP_URL = "https://id.falconindy.com"

        # We sit behind Envoy + Traefik; honor X-Forwarded-* headers.
        TRUST_PROXY = "true"
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
        "traefik-ingress.consulcatalog.connect=true",
        "traefik-ingress.http.routers.${NOMAD_JOB_NAME}.rule=Host(`id.falconindy.com`)",
      ]

      connect {
        sidecar_service {
          proxy {
            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9102"
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
