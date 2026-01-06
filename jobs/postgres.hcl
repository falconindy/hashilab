job "postgres" {
  datacenters = ["dc1"]
  type        = "service"

  group "postgres" {
    network {
      mode = "bridge"

      port "envoy_metrics" { to = 9102 }
    }

    service {
      name         = "postgres"
      port         = 5432
      address_mode = "host"

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
        interval = "5s"
        task     = "server"
        timeout  = "2s"
      }
    }

    task "server" {
      driver = "podman"

      config {
        image = "postgres:17.7"

        volumes = [
          "/clusterdata/postgres:/appdata/postgres",
        ]
      }

      vault {}

      template {
        data        = <<EOF
          {{ with secret "kv/data/default/postgres" }}
            POSTGRES_PASSWORD="{{ .Data.data.postgres_password }}"
          {{ end }}
        EOF
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
