# Used by the cluster-config-snapshotter job (role raft-snapshotter). Vault's own
# raft snapshot is read straight from sys/; Consul and Nomad snapshot save both
# require a management token, so mint short-lived ones from the Consul/Nomad
# secrets engines.
path "sys/storage/raft/snapshot" {
  capabilities = ["read"]
}

path "consul/creds/mgmt" {
  capabilities = ["read"]
}

path "nomad/creds/mgmt" {
  capabilities = ["read"]
}
