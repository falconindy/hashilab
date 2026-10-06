job "omada-mcp" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "MCP server exposing the TP-Link Omada controller API to AI agents"
    link {
      label = "GitHub"
      url   = "https://github.com/MiguelTVMS/tplink-omada-mcp"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/r/jmtvms/tplink-omada-mcp"
    }
  }

  group "omada-mcp" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "envoy_metrics" { to = 9102 }
    }

    task "server" {
      driver = "docker"
      user   = "1000:1000"

      config {
        image = "jmtvms/tplink-omada-mcp:v0.15.0"

        cap_drop     = ["all"]
        security_opt = ["no-new-privileges=true"]

        volumes = [
          "/etc/ssl/certs/ca-certificates.crt:/etc/ssl/certs/ca-certificates.crt:ro",
        ]
      }

      env {
        OMADA_BASE_URL      = "https://omada-controller.service.home:8043"
        NODE_EXTRA_CA_CERTS = "/etc/ssl/certs/ca-certificates.crt"

        # Read-only by default across dashboard/client-insights/clients/devices.
        # No write categories are enabled; the only write tools this server
        # ships today (setClientRateLimit, setClientRateLimitProfile,
        # disableClientRateLimit) live under clients:w — add it deliberately
        # once the read-only posture has been exercised for a while.
        OMADA_TOOL_CATEGORIES = "dashboard:r,client-insights:r,clients:r,devices-all:r"

        MCP_SERVER_USE_HTTP  = "true"
        MCP_HTTP_BIND_ADDR   = "127.0.0.1"
        MCP_HTTP_PORT        = "3000"
        MCP_SERVER_LOG_LEVEL = "info"
      }

      vault {}

      template {
        data        = <<-EOF
          {{ with (secret "kv/data/default/omada-mcp").Data.data }}
            OMADA_CLIENT_ID="{{ .openapi_client_id }}"
            OMADA_CLIENT_SECRET="{{ .openapi_secret_id }}"
            OMADA_OMADAC_ID="{{ .omadac_id }}"
            OMADA_SITE_ID="{{ .site_id }}"
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
      name = "omada-mcp"
      port = 3000

      # No app-layer auth in front of the HTTP transport (no bearer/API-key
      # support upstream as of v0.15.0) — traefik.enable=true + the
      # internal-only middleware (RFC1918-only) is the only gate today.
      # Revisit with Traefik BasicAuth if that's not enough.
      tags = [
        "traefik.enable=true",
        "homelabdash.hide",
      ]

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}"
      }

      connect {
        sidecar_service {
          proxy {
            transparent_proxy {
              no_dns = true
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
