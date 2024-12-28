# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: BUSL-1.1

# Full configuration options can be found at https://developer.hashicorp.com/vault/docs/configuration

ui = true

disable_mlock = true

storage "raft" {
  path = "/opt/vault"

  retry_join {
    auto_join_scheme        = "https"
    leader_api_addr         = "https://10.0.100.100:8200"
    leader_tls_servername   = "10.0.100.100"
    leader_ca_cert_file     = "/opt/vault/tls/vault-agent-ca.pem"
    leader_client_cert_file = "/opt/vault/tls/global-server-vault-0.pem"
    leader_client_key_file  = "/opt/vault/tls/global-server-vault-0-key.pem"
  }

  retry_join {
    auto_join_scheme        = "https"
    leader_api_addr         = "https://10.0.100.101:8200"
    leader_tls_servername   = "10.0.100.101"
    leader_ca_cert_file     = "/opt/vault/tls/vault-agent-ca.pem"
    leader_client_cert_file = "/opt/vault/tls/global-server-vault-0.pem"
    leader_client_key_file  = "/opt/vault/tls/global-server-vault-0-key.pem"
  }

  retry_join {
    auto_join_scheme        = "https"
    leader_api_addr         = "https://10.0.100.102:8200"
    leader_tls_servername   = "10.0.100.102"
    leader_ca_cert_file     = "/opt/vault/tls/vault-agent-ca.pem"
    leader_client_cert_file = "/opt/vault/tls/global-server-vault-0.pem"
    leader_client_key_file  = "/opt/vault/tls/global-server-vault-0-key.pem"
  }
}

# HTTPS listener
listener "tcp" {
  address            = "0.0.0.0:8200"
  tls_disable        = 0
  tls_cert_file      = "/opt/vault/tls/global-server-vault-0.pem"
  tls_key_file       = "/opt/vault/tls/global-server-vault-0-key.pem"
  tls_client_ca_file = "/opt/vault/tls/vault-agent-ca.pem"
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

api_addr     = "https://{{ GetInterfaceIP \"enp1s0\" }}:8200"
cluster_addr = "https://{{ GetInterfaceIP \"enp1s0\" }}:8201"

# Example AWS KMS auto unseal
#seal "awskms" {
#  region = "us-east-1"
#  kms_key_id = "REPLACE-ME"
#}

# Example HSM auto unseal
#seal "pkcs11" {
#  lib            = "/usr/vault/lib/libCryptoki2_64.so"
#  slot           = "0"
#  pin            = "AAAA-BBBB-CCCC-DDDD"
#  key_label      = "vault-hsm-key"
#  hmac_key_label = "vault-hsm-hmac-key"
#}
