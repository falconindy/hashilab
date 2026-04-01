job "cloudflare-ddns" {
  datacenters = ["dc1"]
  type        = "service"

  group "cloudflare-ddns" {
    network {
      dns {
        servers = ["172.17.0.1"]
      }
    }

    task "updater" {
      driver = "docker"
      user   = "1000:1000"

      config {
        image        = "favonia/cloudflare-ddns:1.16.1"
        network_mode = "host"
        cap_drop     = ["all"]
        security_opt = ["no-new-privileges=true"]
      }

      vault {}

      template {
        data        = <<-EOF
          {{ with secret "kv/data/default/cloudflare-ddns" }}
            CLOUDFLARE_API_TOKEN="{{ .Data.data.api_token }}"
          {{ end }}
        EOF
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
