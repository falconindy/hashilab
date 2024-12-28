# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: BUSL-1.1

# Full configuration options can be found at https://developer.hashicorp.com/nomad/docs/configuration

server {
  enabled          = true
  bootstrap_expect = 3
  raft_protocol    = 3

  encrypt          = "cxmhW6EIIdg0KU8xtwB29EpiJ5yiUdJaYkJYjUC/734="
}
