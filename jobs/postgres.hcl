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

      # postgres's own STOPSIGNAL is SIGINT (fast shutdown); asserted here
      # rather than relying on the image default, with enough kill_timeout
      # that a busy shutdown doesn't get SIGKILLed into crash recovery.
      kill_signal  = "SIGINT"
      kill_timeout = "30s"

      config {
        image = "postgres:17.10"

        cap_drop     = ["all"]
        security_opt = ["no-new-privileges=true"]

        volumes = [
          "/clusterdata/postgres:/appdata/postgres",
          "/clusterdata/postgres-backups:/appdata/backups",
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

      # Logical backup of every database plus role/grant globals, run
      # in-container so pg_dump/pg_dumpall always match the running server
      # build and the dump goes over the local unix socket — no Consul
      # intention needed, no second copy of POSTGRES_PASSWORD in Vault KV.
      # Triggered daily by the "postgres" group in
      # jobs/cluster-config-snapshotter.hcl; safe to run by hand too:
      #   nomad job action -job postgres -group postgres -task server backup
      #
      # Publish is a single rename(2): everything is written under a
      # .work/<ts> scratch dir and only renamed into place once every dump in
      # the set has succeeded, so a torn or partial run can never be mistaken
      # for a good one. MANIFEST/SHA256SUMS are left world-readable so the
      # raw_exec trigger (root, over the same NFS mount) can verify a run
      # without needing uid 999; the dumps themselves stay 0600 since the
      # globals dump carries every role's password hash.
      action "backup" {
        command = "/bin/sh"
        args = ["-c", <<-EOF
            set -eu

            root=/appdata/backups
            ts=$(date -u +%Y%m%dT%H%M%SZ)
            work="$root/.work/$ts"
            dest="$root/$ts"

            [ -d "$root" ] || { echo "FATAL: $root is not mounted" >&2; exit 1; }
            # POSTGRES_PASSWORD normally arrives via the container env, but
            # source the rendered file too so this doesn't depend on exec
            # inheriting create-time env.
            [ -r /secrets/env ] && . /secrets/env

            umask 077
            mkdir -p "$root/.work" "$root/textfile"
            chmod 755 "$root/textfile" # read by node-exporter, a separate container
            mkdir "$work"
            trap 'rm -rf "$work"' EXIT

            export PGHOST=/var/run/postgresql PGUSER=postgres PGCONNECT_TIMEOUT=10

            echo "== globals (roles, grants) =="
            pg_dumpall -w --globals-only > "$work/globals.sql"

            dbs=$(psql -w -Atc "select datname from pg_database where not datistemplate and datallowconn order by 1")
            [ -n "$dbs" ] || { echo "FATAL: enumerated zero databases" >&2; exit 1; }

            for db in $dbs; do
              echo "== $db =="
              pg_dump -w -Fc -Z 3 -d "$db" -f "$work/$db.dump"
            done

            (cd "$work" && sha256sum globals.sql *.dump > SHA256SUMS)
            {
              echo "timestamp=$ts"
              echo "server_version=$(psql -w -Atc 'show server_version')"
              echo "databases=$dbs"
              echo "status=ok"
            } > "$work/MANIFEST"
            chmod 644 "$work/MANIFEST" "$work/SHA256SUMS"
            chmod 755 "$work"

            # Atomic publish, then atomic pointer flip.
            trap - EXIT
            mv "$work" "$dest"
            ln -sfn "$ts" "$root/.latest.tmp"
            mv -T "$root/.latest.tmp" "$root/latest"

            # node_exporter textfile metric: staleness alerting has nothing
            # else to key off, since a backup is otherwise invisible to
            # Prometheus between runs.
            {
              echo "# HELP postgres_backup_last_success_timestamp_seconds Unix time of the last successful logical backup."
              echo "# TYPE postgres_backup_last_success_timestamp_seconds gauge"
              echo "postgres_backup_last_success_timestamp_seconds $(date +%s)"
            } > "$root/textfile/postgres_backup.prom.tmp"
            chmod 644 "$root/textfile/postgres_backup.prom.tmp"
            mv -T "$root/textfile/postgres_backup.prom.tmp" "$root/textfile/postgres_backup.prom"

            # Retention: 14 days, floor of 7 sets so a stretch of failed runs
            # can't prune its way down to nothing to restore from.
            ls -1 "$root" | grep -E '^[0-9]{8}T[0-9]{6}Z$' | sort -r | tail -n +8 |
              while read -r d; do
                find "$root/$d" -maxdepth 0 -mtime +14 -exec rm -rf {} +
              done
            find "$root/.work" -mindepth 1 -maxdepth 1 -mtime +1 -exec rm -rf {} +

            echo "BACKUP_OK $ts"
          EOF
        ]
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
