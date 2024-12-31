# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: BUSL-1.1

# Full configuration options can be found at https://developer.hashicorp.com/nomad/docs/configuration

client {
  enabled = true

  max_kill_timeout = "30s"

  gc_interval              = "1m"
  gc_disk_usage_threshold  = 80
  gc_inode_usage_threshold = 70
  gc_parallel_destroys     = 2

  meta {
    # label = "value"
  }
}
