path "pki_int_internal/issue/intermediate" {
  capabilities = ["update"]
}

# vault-agent on the omada host (bastion) issues omada-controller's server cert,
# then pushes the rendered chain + key here via `vault kv put` (omada-push-kv.sh).
# The omada-controller job reads it back through its default workload-identity KV
# scope (kv/data/default/omada-controller/*).
path "kv/data/default/omada-controller/cert" {
  capabilities = ["create", "update"]
}
