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
}
