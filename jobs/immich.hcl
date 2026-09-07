job "immich" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "Self-hosted photo and video backup solution"
    link {
      label = "Upstream"
      url   = "https://immich.app"
    }
    link {
      label = "GitHub"
      url   = "https://github.com/immich-app/immich"
    }
    link {
      label = "Docs"
      url   = "https://docs.immich.app"
    }
  }

  constraint {
    attribute = "${meta.has_quicksync}"
    operator  = "="
    value     = "true"
  }

  group "immich" {
    network {
      mode = "bridge"

      port "envoy_metrics" { to = 9102 }
    }

    # Redis's append-only file. Losing it strands assets mid-processing (they
    # get reprocessed), so persist across restarts, but it's not worth NFS.
    ephemeral_disk {
      size    = 512 # MB
      migrate = true
    }

    task "server" {
      driver = "docker"

      config {
        image = "ghcr.io/immich-app/immich-server:v3.1.0"

        cap_drop     = ["all"]
        security_opt = ["no-new-privileges=true"]

        volumes = [
          "/clusterdata/immich/library:/data:rw",
        ]
      }

      env {
        TZ = "America/New_York"

        IMMICH_PORT           = "2283"
        IMMICH_MEDIA_LOCATION = "/data"

        DB_HOSTNAME         = "127.0.0.1"
        DB_PORT             = "5432"
        DB_USERNAME         = "immich"
        DB_DATABASE_NAME    = "immich"
        DB_VECTOR_EXTENSION = "vectorchord"

        REDIS_HOSTNAME = "127.0.0.1"
        REDIS_PORT     = "6379"

        IMMICH_MACHINE_LEARNING_URL = "http://127.0.0.1:3003"
      }

      vault {}

      template {
        data        = <<-EOF
          {{ with (secret "kv/data/default/immich").Data.data }}
            DB_PASSWORD="{{ .postgres_password }}"
          {{ end }}
        EOF
        destination = "secrets/env"
        env         = true
      }

      resources {
        cpu        = 1500
        memory     = 2048
        memory_max = 3072
      }
    }

    task "machine-learning" {
      driver = "docker"

      config {
        image = "ghcr.io/immich-app/immich-machine-learning:v3.1.0-openvino"

        cap_drop     = ["all"]
        security_opt = ["no-new-privileges=true"]

        volumes = [
          "/clusterdata/immich/model-cache:/cache:rw",
        ]

        devices = [
          {
            host_path      = "/dev/dri",
            container_path = "/dev/dri",
          },
        ]
      }

      env {
        TZ                         = "America/New_York"
        MACHINE_LEARNING_WORKERS   = "1"
        MACHINE_LEARNING_MODEL_TTL = "300"
      }

      resources {
        cpu        = 1000
        memory     = 2048
        memory_max = 3072
      }
    }

    task "redis" {
      driver = "docker"

      config {
        image = "valkey/valkey:9"

        cap_add      = ["CHOWN", "DAC_OVERRIDE", "FOWNER", "SETUID", "SETGID"]
        cap_drop     = ["all"]
        security_opt = ["no-new-privileges=true"]

        args = [
          "--bind", "127.0.0.1",
          "--dir", "/alloc/data",
          "--appendonly", "yes",
        ]
      }

      env {
        TZ = "America/New_York"
      }

      resources {
        cpu    = 100
        memory = 256
      }
    }

    task "database" {
      driver = "docker"
      user   = "999:999"

      # Use postgres's recommended "fast" shutdown via SIGINT.
      kill_signal  = "SIGINT"
      kill_timeout = "30s"

      config {
        image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0"

        # The image's entrypoint copies a DB_STORAGE_TYPE-selected template to
        # /etc/postgresql/postgresql.conf (with shared_preload_libraries=vchord.so
        # baked in) and expects it passed via config_file; overriding `args`
        # drops that default, so it has to be repeated here.
        args = [
          "-c", "config_file=/etc/postgresql/postgresql.conf",
          "-c", "listen_addresses=127.0.0.1",
        ]

        shm_size     = 134217728 # 128MiB
        cap_drop     = ["all"]
        security_opt = ["no-new-privileges=true"]

        volumes = [
          "/clusterdata/immich/db:/appdata/postgres",
        ]
      }

      vault {}

      template {
        data        = <<-EOF
          {{ with (secret "kv/data/default/immich").Data.data }}
            POSTGRES_PASSWORD="{{ .postgres_password }}"
          {{ end }}
        EOF
        destination = "secrets/env"
        env         = true
      }

      resources {
        cpu    = 500
        memory = 1024
      }

      env {
        TZ                   = "America/New_York"
        POSTGRES_DB          = "immich"
        POSTGRES_USER        = "immich"
        POSTGRES_INITDB_ARGS = "--data-checksums"
        PGDATA               = "/appdata/postgres"
        DB_STORAGE_TYPE      = "HDD"
      }
    }

    service {
      name = "immich"
      port = 2283

      tags = [
        "traefik.enable=true",
        "traefik-ingress.enable=true",
      ]

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}"
      }

      connect {
        sidecar_service {}

        sidecar_task {
          resources {
            cpu    = 50
            memory = 48
          }
        }
      }

      check {
        type     = "http"
        path     = "/api/server/ping"
        interval = "10s"
        timeout  = "2s"
        expose   = true
      }
    }
  }
}
