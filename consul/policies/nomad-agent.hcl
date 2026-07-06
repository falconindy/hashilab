# The Nomad *agent* token (distinct from per-allocation workload-identity
# tokens). Delivered to the Nomad servers/clients as CONSUL_HTTP_TOKEN. Covers
# what the agent itself does against Consul: auto-join discovery, registering
# its own `nomad`/`nomad-client` services + health checks. It also needs to be
# capable of *de*registering services from the consul catalog and thus needs
# broad service_prefix permissions. The per-service tokens for actual workloads
# come from the nomad-workloads auth method, not this.
agent_prefix "" {
  policy = "read"
}

node_prefix "" {
  policy = "write"
}

service_prefix "" {
  policy = "write"
}
