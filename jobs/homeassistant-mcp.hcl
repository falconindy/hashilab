job "homeassistant-mcp" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "MCP server exposing Home Assistant to AI agents"
    link {
      label = "GitHub"
      url   = "https://github.com/homeassistant-ai/ha-mcp"
    }
    link {
      label = "Container Image"
      url   = "https://github.com/homeassistant-ai/ha-mcp/pkgs/container/ha-mcp"
    }
  }

  group "homeassistant-mcp" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "envoy_metrics" { to = 9102 }
    }

    task "server" {
      driver = "docker"

      # Image bakes in a fixed mcpuser (999:999) rather than a Nomad-side
      # `user` override — /clusterdata/ha-mcp must be chown'd 999:999 on the
      # host before first run, or the settings/tool-config volume falls back
      # to an in-container tmpdir and loses state on every restart.
      config {
        image   = "ghcr.io/homeassistant-ai/ha-mcp:8.4.3"
        command = "ha-mcp-web"

        cap_drop     = ["all"]
        security_opt = ["no-new-privileges=true"]

        volumes = [
          "/clusterdata/ha-mcp:/home/mcpuser/.ha-mcp:rw",
        ]
      }

      env {
        HOMEASSISTANT_URL = "http://homeassistant.virtual.home"

        # Loopback-only: the Envoy sidecar is the sole way in, so nothing on
        # the bridge can reach the server around the mesh.
        MCP_HOST    = "127.0.0.1"
        MCP_PORT    = "8086"
        MCP_HEALTHZ = "true" # opt-in /healthz; doesn't echo the secret path
        LOG_LEVEL   = "INFO"
      }

      vault {}

      # MCP_SECRET_PATH is the actual auth boundary in standard HTTP mode
      # (URL-path secrecy per ha-mcp's SECURITY.md) — Traefik/internal-only
      # is defense in depth on top of it, not a substitute. Generate once
      # with:
      #   python3 -c 'import secrets; print("/private_" + secrets.token_urlsafe(16))'
      # and store it in Vault rather than the job file, since this file is
      # checked into git. HOMEASSISTANT_TOKEN is a long-lived access token
      # from the HA profile page.
      template {
        data        = <<-EOF
          {{ with (secret "kv/data/default/homeassistant-mcp").Data.data }}
            HOMEASSISTANT_TOKEN="{{ .ha_token }}"
            MCP_SECRET_PATH="{{ .mcp_secret_path }}"
          {{ end }}
        EOF
        destination = "secrets/env"
        env         = true
      }

      resources {
        cpu    = 200
        memory = 512
      }
    }

    service {
      name = "homeassistant-mcp"
      port = 8086

      # Connect a client to https://homeassistant-mcp.service.home<MCP_SECRET_PATH>;
      # Traefik proxies the path through untouched. Write tools can be fenced
      # off with READ_ONLY_MODE=true (or the settings-UI toggle, persisted in
      # /clusterdata/ha-mcp).
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
