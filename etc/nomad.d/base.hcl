# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: BUSL-1.1

# Full configuration options can be found at https://developer.hashicorp.com/nomad/docs/configuration

data_dir  = "/opt/nomad/data"
bind_addr = "0.0.0.0"

advertise {
  http  = "{{ GetInterfaceIP \"enp1s0\" }}:4646"
  rpc   = "{{ GetInterfaceIP \"ens1s0\" }}:4647"
  serf  = "{{ GetInterfaceIP \"ens1s0\" }}:4648"
}

consul {
  address = "localhost:8500"
  checks_use_advertise = true

  auto_advertise = true

  server_auto_join = true
  client_auto_join = true
}

plugin "docker" {
  config {
    allow_privileged = true
    allow_caps = ["ALL"]

    volumes {
      enabled = "true"
    }
  }
}
