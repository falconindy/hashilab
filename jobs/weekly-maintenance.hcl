job "weekly-maintenance" {
  datacenters = ["*"]
  type        = "sysbatch"

  periodic {
    crons            = ["15 3 * * Sun"] # run every Sunday at 3:15
    time_zone        = "America/New_York"
    prohibit_overlap = true
  }

  group "weekly-maintenance" {
    task "oneshot" {
      driver = "raw_exec"

      config {
        command = "/bin/sh"
        # add additional weekly maintenance actions as desired
        args = ["-c", <<EOF
            echo "running weekly maintenance on ${node.unique.name}.home"
            apt autopurge -y
            apt autoclean
            echo "finished cleaning up outdated apt packages"

            journalctl --vacuum-time=7d 2>&1
            echo "finished purging old log data from journald"

            echo "Running podman system prune..."
            # Prune unused containers, networks, images (dangling), and build cache
            podman system prune -f

            # Prune unused images older than 1 week (including non-dangling)
            podman image prune -a -f --filter "until=168h"
          EOF
        ]
      }

      resources {
        memory = 100
        cpu    = 100
      }
    }
  }
}
