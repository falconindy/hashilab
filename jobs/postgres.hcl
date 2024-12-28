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

      volume_mount {
        volume      = "postgres"
        destination = "/appdata/postgres"
        read_only   = false
      }

      resources {
        cpu    = 1000 # MHz
        memory = 1024 # MB
      }

      config {
        image      = "postgres:15"
        privileged = true
        ports      = ["db"]
      }

      env {
        POSTGRES_DB       = "postgres"
        POSTGRES_USER     = "postgres"
        POSTGRES_PASSWORD = "${var.postgres_password}"
        PGDATA            = "/appdata/postgres"
      }
    }

  }
}

variable postgres_password {
  type = string
}
