# Token for Vault's `service_registration "consul"` block (os/etc/vault.d/
# vault.hcl.j2). Vault self-registers the "vault" service with sealed/standby/
# active health, so it needs write on exactly that service and read to resolve
# its own node/agent. Nothing else.
service "vault" {
  policy = "write"
}

node_prefix "" {
  policy = "read"
}

agent_prefix "" {
  policy = "read"
}
