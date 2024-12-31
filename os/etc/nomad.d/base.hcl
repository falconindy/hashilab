# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: BUSL-1.1

# Full configuration options can be found at https://developer.hashicorp.com/nomad/docs/configuration

data_dir  = "/opt/nomad/data"
bind_addr = "0.0.0.0"

advertise {
  http = "{{ GetInterfaceIP \"enp1s0\" }}:4646"
  rpc  = "{{ GetInterfaceIP \"enp1s0\" }}:4647"
  serf = "{{ GetInterfaceIP \"enp1s0\" }}:4648"
}

ui {
  enabled = true

  consul {
    ui_url = "http://consul.service.consul:8500/ui"
  }

  vault {
    ui_url = "https://vault.service.consul:8200/ui"
  }
}

consul {
  address              = "localhost:8500"
  auto_advertise       = true
  checks_use_advertise = true

  server_auto_join = true
  client_auto_join = true
}

acl {
  enabled = true
}

vault {
  enabled = true

  tls_skip_verify = true

  create_from_role = "nomad-cluster"

  default_identity {
    aud = ["vault.io"]
    env = true
    file = true
    ttl = "1h"
  }
}

plugin "docker" {
  config {
    allow_privileged = true
    allow_caps       = ["ALL"]

    volumes {
      enabled = "true"
    }
  }
}
