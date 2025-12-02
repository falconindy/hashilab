job "vault-raft-snapshotter" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["42 2 * * *"] # run every day at 2:42
    prohibit_overlap = true
    time_zone        = "America/New_York"
  }

  group "vault-raft-snapshotter" {
    task "snapshotter" {
      driver = "raw_exec"

      config {
        command = "/bin/sh"
        args = ["-c", <<-EOF
            set -euo pipefail

            out=$(date +/clusterdata/raft-snapshots/raft-%Y%m%dT%H%M%S.snap)

            echo "Saving snapshot to $out..."
            vault operator raft snapshot save "$out"

            echo "Deleting any snapshots older than 30 days"
            find /clusterdata/raft-snapshots -name '*.snap' -type f -mtime +30 -exec rm -v {} +
          EOF
        ]
      }

      vault {
        env  = true
        role = "raft-snapshotter"
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
}
