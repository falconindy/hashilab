# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: BUSL-1.1

# Full configuration options can be found at https://developer.hashicorp.com/nomad/docs/configuration

server {
  enabled          = true
  bootstrap_expect = 3
  raft_protocol    = 3

  default_scheduler_config {
    scheduler_algorithm = "spread"
  }

  # Gossip encryption should be used, but it's only specified in config during
  # initial setup. Manage via `nomad operator gossip keyring`.
  # encrypt = ""
}
