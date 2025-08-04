job "postgres" {
  datacenters = ["dc1"]
  type        = "service"

  group "postgres" {
    volume "postgres" {
      type            = "csi"
      read_only       = false
      source          = "postgres"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    network {
      dns {
        servers = ["172.17.0.1"]
      }

      port "db" {
        static = 5432
      }
    }

    service {
      name = "postgres"
      port = "db"

      check {
        type     = "tcp"
        port     = "db"
        interval = "30s"
        timeout  = "2s"
      }
    }

    task "postgres" {
      driver = "docker"

      config {
        image = "postgres:17.5"
        ports = ["db"]
      }

      volume_mount {
        volume      = "postgres"
        destination = "/appdata/postgres"
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
