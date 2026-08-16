job "postgres" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "The world's most advanced open source relational database"
    link {
      label = "Upstream"
      url   = "https://www.postgresql.org"
    }
    link {
      label = "GitHub"
      url   = "https://github.com/postgres/postgres"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/_/postgres"
    }
  }

  group "postgres" {
    network {
      mode = "bridge"

      port "envoy_metrics" { to = 9102 }
    }

    task "server" {
      driver = "docker"
      user   = "999:999"

      # Use postgres's recommended "fast" shutdown via SIGINT.
      kill_signal  = "SIGINT"
      kill_timeout = "30s"

      config {
        image = "postgres:17.11"

        args = [
          "-c", "listen_addresses=127.0.0.1",
          "-c", "shared_buffers=128MB",
          "-c", "effective_cache_size=384MB",
          "-c", "max_connections=40",
          "-c", "autovacuum_vacuum_scale_factor=0.1",
          "-c", "log_min_duration_statement=250ms",
        ]

        shm_size     = 134217728 # 128MiB
        cap_drop     = ["all"]
        security_opt = ["no-new-privileges=true"]

        volumes = [
          "/clusterdata/postgres:/appdata/postgres",
        ]
      }

      vault {}

      template {
        data        = <<EOF
          {{ with (secret "kv/data/default/postgres").Data.data }}
            POSTGRES_PASSWORD="{{ .postgres_password }}"
          {{ end }}
        EOF
        destination = "secrets/env"
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

    service {
      name = "postgres"
      port = 5432

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}"
      }

      connect {
        sidecar_service {
          proxy {
            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9102"
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
        type     = "script"
        command  = "/usr/bin/pg_isready"
        args     = ["-U", "postgres"]
        interval = "5s"
        task     = "server"
        timeout  = "2s"
      }
    }
  }
}
