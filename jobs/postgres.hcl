job "postgres" {
  datacenters = ["dc1"]
  type        = "service"

  group "postgres" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "db" {
        static = 5432
      }
    }

    service {
      name         = "postgres"
      port         = "db"
      address_mode = "host"

      check {
        type     = "tcp"
        port     = "db"
        interval = "30s"
        timeout  = "2s"
      }
    }

    task "server" {
      driver = "podman"

      config {
        image = "postgres:17.6"
        ports = ["db"]

        volumes = [
          "/clusterdata/postgres:/appdata/postgres",
        ]
      }

      vault {}

      identity {
        name = "vault_default"
        aud  = ["vault.io"]
        ttl  = "1h"
      }

      template {
        data        = <<EOH
          {{ with secret "kv/data/default/postgres" }}
            POSTGRES_PASSWORD="{{ .Data.data.postgres_password }}"
          {{ end }}
      EOH
        destination = "secrets/auth.env"
        env         = true
      }

      resources {
        cpu    = 200
        memory = 512
      }

      env {
        POSTGRES_DB   = "postgres"
        POSTGRES_USER = "postgres"
        PGDATA        = "/appdata/postgres"
      }
    }
  }
}
