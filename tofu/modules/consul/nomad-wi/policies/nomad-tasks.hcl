# Policy bound (via the `nomad-tasks` Consul role) to Nomad allocations that have
# NO service block — i.e. tasks that only need to *read* the catalog/KV from a
# `template` stanza (consul-template). Service-bearing allocations don't use this;
# they get a per-service token via the `service` binding rule instead.
#
# Kept deliberately minimal: catalog read only, no KV grant (the mesh currently
# stores nothing in Consul KV). Widen here if a job's template needs specific KV.
service_prefix "" {
  policy = "read"
}

node_prefix "" {
  policy = "read"
}
