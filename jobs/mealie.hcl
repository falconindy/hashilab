job "mealie" {
  group "mealie" {
    volume "mealie" {
      type            = "csi"
      read_only       = false
      source          = "mealie"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    network {
      mode = "bridge"
      port "http" {
        to = 9000
      }
    }

    task "mealie" {
      driver = "docker"

      config {
        image = "ghcr.io/mealie-recipes/mealie:v2.5.0"
        ports = ["http"]
      }

      volume_mount {
        volume      = "mealie"
        destination = "/app/data/mealie"
        read_only   = false
      }

      vault {}

      identity {
        name = "vault_default"
        aud  = ["vault.io"]
        ttl  = "1h"
      }

      template {
        data        = <<EOH
          {{ with secret "kv/data/default/mealie" }}
            POSTGRES_PASSWORD="{{ .Data.data.postgres_password }}"
            OIDC_CLIENT_SECRET="{{ .Data.data.google_oauth_secret }}"
          {{ end }}
      EOH
        destination = "secrets/auth.env"
        env         = true
      }

      env {
        ALLOW_SIGNUP = "false"
        PUID         = "1000"
        PGID         = "1000"
        BASE_URL     = "http://mealie.service.home"

        DB_ENGINE       = "postgres"
        POSTGRES_USER   = "mealie"
        POSTGRES_SERVER = "postgres.service.home"
        POSTGRES_PORT   = "5432"

        OIDC_AUTH_ENABLED      = "true"
        OIDC_PROVIDER_NAME     = "Falcon Industries"
        OIDC_CONFIGURATION_URL = "https://accounts.google.com/.well-known/openid-configuration"
        OIDC_SIGNUP_ENABLED    = "false"
        OIDC_CLIENT_ID         = "65107715713-2pmo4gs9sp8jcbdjm9kl259tnmftji3i.apps.googleusercontent.com"
      }

      service {
        name = "mealie"
        port = "http"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.${NOMAD_JOB_NAME}.rule=Host(`${NOMAD_JOB_NAME}.falconindy.com`)",
          "traefik.http.routers.${NOMAD_JOB_NAME}.entrypoints=https",
          "traefik.http.routers.${NOMAD_JOB_NAME}.tls.certresolver=letsEncrypt",
        ]
      }

      resources {
        cpu    = 100
        memory = 512
      }
    }
  }
}
