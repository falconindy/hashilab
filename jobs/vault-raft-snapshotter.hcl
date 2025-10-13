job "vault-raft-snapshotter" {
  datacenters = ["dc1"]
  type = "batch"

  periodic {
    crons            = ["42 2 * * *"] # run every day at 2:42
    prohibit_overlap = true
  }

  group "vault-raft-snapshotter" {
    task "snapshotter" {
      driver = "raw_exec"

      config {
        command = "bash"
        args = ["-c", <<EOT
            set -euo pipefail

            out=$(date +/clusterdata/raft-snapshots/raft-%Y%m%dT%H%M%S.snap)

            echo "Saving snapshot to $out..."
            vault operator raft snapshot save "$out"

            echo "Deleting any snapshots older than 30 days"
            find /clusterdata/raft-snapshots -name '*.snap' -type f -mtime +30 -exec rm -v {} +
          EOT
        ]
      }

      vault {
        env = true
        role = "raft-snapshotter"
      }

      env {
        VAULT_ADDR = "https://active.vault.service.home:8200"
      }

      identity {
        name = "vault_default"
        aud  = ["vault.io"]
        ttl  = "1h"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}

