# Bound (via the `traefik` Consul role + a job-scoped nomad-workloads binding
# rule, module.consul_nomad_wi) to Traefik's TASK workload identity. Traefik's
# consulCatalog provider runs connectaware, so it fetches a Connect leaf cert for
# itself from /v1/agent/connect/ca/leaf/traefik — which requires service:write on
# "traefik". The task identity otherwise binds only to nomad-tasks (catalog read),
# enough for discovery + upstream resolution but NOT for the leaf; this adds
# exactly that one write. Under default_policy = "deny" the anonymous fallback is
# read-only, so without this Traefik's mesh dialing to backends stops.
#
# Catalog read comes from the nomad-tasks role the same token also carries, so
# it's deliberately not repeated here.
service "traefik" {
  policy = "write"
}
