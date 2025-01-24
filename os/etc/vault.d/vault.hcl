# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: BUSL-1.1

# Full configuration options can be found at https://developer.hashicorp.com/vault/docs/configuration

ui = true

disable_mlock = true

api_addr     = "https://{{ GetInterfaceIP \"enp1s0\" }}:8200"
cluster_addr = "https://{{ GetInterfaceIP \"enp1s0\" }}:8201"

storage "raft" {
  path = "/opt/vault"

  retry_join {
    auto_join_scheme        = "https"
    leader_api_addr         = "https://10.0.100.100:8200"
    leader_tls_servername   = "vault.service.home"
    leader_ca_cert_file     = "/opt/vault/tls/home-agent-ca.pem"
    leader_client_cert_file = "/opt/vault/tls/global-server-home-0.pem"
    leader_client_key_file  = "/opt/vault/tls/global-server-home-0-key.pem"
  }

  retry_join {
    auto_join_scheme        = "https"
    leader_api_addr         = "https://10.0.100.101:8200"
    leader_tls_servername   = "vault.service.home"
    leader_ca_cert_file     = "/opt/vault/tls/home-agent-ca.pem"
    leader_client_cert_file = "/opt/vault/tls/global-server-home-0.pem"
    leader_client_key_file  = "/opt/vault/tls/global-server-home-0-key.pem"
  }

  retry_join {
    auto_join_scheme        = "https"
    leader_api_addr         = "https://10.0.100.102:8200"
    leader_tls_servername   = "vault.service.home"
    leader_ca_cert_file     = "/opt/vault/tls/home-agent-ca.pem"
    leader_client_cert_file = "/opt/vault/tls/global-server-home-0.pem"
    leader_client_key_file  = "/opt/vault/tls/global-server-home-0-key.pem"
  }
}

telemetry {
  disable_hostname = true
  prometheus_retention_time = "12h"
}

# HTTP listener for local connections
listener "tcp" {
  address     = "172.17.0.1:8200"
  tls_disable = true
}

# HTTPS listener
listener "tcp" {
  address            = "{{ GetInterfaceIP \"enp1s0\" }}:8200"
  tls_cert_file      = "/opt/vault/tls/global-server-home-0.pem"
  tls_key_file       = "/opt/vault/tls/global-server-home-0-key.pem"
  tls_client_ca_file = "/opt/vault/tls/home-agent-ca.pem"
}

seal "gcpckms" {
  project     = "stunning-chain-397719"
  region      = "global"
  key_ring    = "vault"
  crypto_key  = "unseal"
  credentials = "/opt/vault/gcp-kms-creds.json"
}

service_registration "consul" {
  address = "http://127.0.0.1:8500"
}
