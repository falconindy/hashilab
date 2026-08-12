job "cluster-config-snapshotter" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["42 2 * * *"] # run every day at 2:42
    prohibit_overlap = true
    time_zone        = "America/New_York"
  }

  vault {
    env  = true
    role = "raft-snapshotter"
  }

  group "vault" {
    task "snapshotter" {
      driver = "raw_exec"

      config {
        command = "/bin/sh"
        args = ["-c", <<-EOF
            set -e

            out=$(date +/clusterdata/vault-snapshots/vault-%Y%m%dT%H%M%S.snap)

            echo "Saving snapshot to $out..."
            vault operator raft snapshot save "$out"

            echo "Deleting any snapshots older than 30 days"
            find /clusterdata/vault-snapshots -name '*.snap' -type f -mtime +30 -exec rm -v {} +
          EOF
        ]
      }

      env {
        VAULT_ADDR = "https://active.vault.service.home:8200"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }

  group "consul" {
    task "snapshotter" {
      driver = "raw_exec"

      config {
        command = "/bin/sh"
        args = ["-c", <<-EOF
            set -e

            out=$(date +/clusterdata/consul-snapshots/consul-%Y%m%dT%H%M%S.snap)

            echo "Saving snapshot to $out..."
            consul snapshot save -stale "$out"

            echo "Deleting any snapshots older than 30 days"
            find /clusterdata/consul-snapshots -name '*.snap' -type f -mtime +30 -exec rm -v {} +
          EOF
        ]
      }

      template {
        data        = <<-EOF
          {{ with secret "consul/creds/mgmt" }}
            CONSUL_HTTP_TOKEN="{{ .Data.token }}"
          {{ end }}
        EOF
        destination = "secrets/env"
        env         = true
      }

      env {
        CONSUL_HTTP_ADDR = "https://consul.service.home:8501"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }

  group "nomad" {
    task "snapshotter" {
      driver = "raw_exec"

      config {
        command = "/bin/sh"
        args = ["-c", <<-EOF
            set -e

            out=$(date +/clusterdata/nomad-snapshots/nomad-%Y%m%dT%H%M%S.snap)

            echo "Saving snapshot to $out..."
            nomad operator snapshot save -stale "$out"

            echo "Deleting any snapshots older than 30 days"
            find /clusterdata/nomad-snapshots -name '*.snap' -type f -mtime +30 -exec rm -v {} +
          EOF
        ]
      }

      template {
        data        = <<-EOF
          {{ with secret "nomad/creds/mgmt" }}
            NOMAD_TOKEN="{{ .Data.secret_id }}"
          {{ end }}
        EOF
        destination = "secrets/env"
        env         = true
      }

      env {
        NOMAD_ADDR = "https://nomad.service.home:4646"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }

  # Postgres logical dumps. The dump itself is an `action "backup"` on the
  # postgres job's server task (jobs/postgres.hcl) — running it in-container
  # means pg_dump always matches the server build, the dump goes over the
  # local unix socket, and no second copy of POSTGRES_PASSWORD has to exist
  # in KV. This group is only the scheduler plus a success check; it lives
  # here rather than as its own job because `nomad job action` needs
  # alloc-exec + read-job + list-jobs, which this job's raft-snapshotter role
  # already grants via nomad/creds/mgmt — a bespoke token would buy no real
  # reduction in blast radius, since Nomad OSS ACL policies scope to a
  # namespace, not a single job.
  group "postgres" {
    task "backup" {
      driver = "raw_exec"

      config {
        command = "/bin/sh"
        args = ["-c", <<-EOF
            set -e

            echo "Triggering postgres backup action..."
            nomad job action -job postgres -group postgres -task server backup

            # `nomad job action` does propagate the remote command's exit
            # status, but the exec channel can still drop mid-dump with the
            # dump left running server-side, so also check the artifact: the
            # action only renames a set into place once every dump in it
            # succeeded.
            root=/clusterdata/postgres-backups
            latest=$(readlink "$root/latest")
            grep -qx status=ok "$root/$latest/MANIFEST"
            find "$root/$latest" -maxdepth 0 -mmin -120 | grep -q .

            echo "Backup verified: $latest"
            du -sh "$root/$latest"
          EOF
        ]
      }

      template {
        data        = <<-EOF
          {{ with secret "nomad/creds/mgmt" }}
            NOMAD_TOKEN="{{ .Data.secret_id }}"
          {{ end }}
        EOF
        destination = "secrets/env"
        env         = true
      }

      env {
        NOMAD_ADDR = "https://nomad.service.home:4646"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
