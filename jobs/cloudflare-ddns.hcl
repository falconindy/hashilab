job "cloudflare-ddns" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "A feature-rich and robust Cloudflare DDNS updater"
    link {
      label = "GitHub"
      url   = "https://github.com/favonia/cloudflare-ddns"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/r/favonia/cloudflare-ddns"
    }
  }

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
        image        = "favonia/cloudflare-ddns:1.17.0"
        network_mode = "host"
        cap_drop     = ["all"]
        security_opt = ["no-new-privileges=true"]
      }

      vault {}

      template {
        data        = <<-EOF
          {{ with (secret "kv/data/default/cloudflare-ddns").Data.data }}
            CLOUDFLARE_API_TOKEN="{{ .api_token }}"
          {{ end }}
        EOF
        destination = "secrets/env"
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
