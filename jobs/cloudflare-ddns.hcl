job "cloudflare-ddns" {
  datacenters = ["dc1"]
  type        = "service"

  group "cloudflare-ddns" {
    count = 1

    network {
      dns {
        servers = ["172.17.0.1"]
      }
    }

    task "updater" {
      driver = "podman"

      config {
        image        = "favonia/cloudflare-ddns:1.15.1"
        force_pull   = true
        network_mode = "host"
        cap_drop     = ["all"]
        security_opt = ["no-new-privileges=true"]
      }

      vault {}

      template {
        data        = <<EOH
          {{ with secret "kv/data/default/cloudflare-ddns" }}
            CLOUDFLARE_API_TOKEN="{{ .Data.data.api_token }}"
          {{ end }}
        EOH
        destination = "secrets/auth.env"
        env         = true
      }

      env {
        DOMAINS      = "scoot.falconindy.com"
        IP6_PROVIDER = "none"
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
