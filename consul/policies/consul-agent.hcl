# The Consul *agent* token, set on every agent via `consul acl set-agent-token
# agent` (the consul role reads it from Vault KV, where module.consul_acl stashes
# it). Used for the agent's own anti-entropy: registering its node into the
# catalog and syncing state.
#
# node_prefix "" write is broad (any node) but is the conventional shared-agent-
# token grant; tighten to node "<hostname>" per-host if you mint a token per
# node. service_prefix read lets the agent reconcile service registrations.
node_prefix "" {
  policy = "write"
}

service_prefix "" {
  policy = "read"
}
