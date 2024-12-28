job "cloudflare-ddns" {
  datacenters = ["dc1"]
  type        = "service"

  group "cloudflare-ddns" {
    count = 1

    task "updater" {
      driver = "docker"

      config {
        image        = "favonia/cloudflare-ddns:1.15.1"
        force_pull   = true
        network_mode = "host"
        cap_drop     = ["all"]
        security_opt = ["no-new-privileges=true"]
      }

      env {
        CLOUDFLARE_API_TOKEN = "${var.cloudflare_api_token}"
        DOMAINS              = "scoot.falconindy.com"
        IP6_PROVIDER         = "none"
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}

variable cloudflare_api_token {
  type = string
}
