# Bound (via the `traefik-ingress` Consul role + a job-scoped nomad-workloads
# binding rule, module.consul_nomad_wi) to the traefik-ingress TASK workload
# identity. Like `traefik`, this ingress runs its consulCatalog provider
# connectaware, so it fetches a Connect leaf cert for itself from
# /v1/agent/connect/ca/leaf/traefik-ingress — which requires service:write on
# "traefik-ingress". The task identity otherwise binds only to nomad-tasks
# (catalog read), enough for discovery but NOT for the leaf; this adds exactly
# that one write. Under default_policy = "deny" the anonymous fallback is
# read-only, so without this the ingress's mesh dialing to backends stops.
#
# Catalog read comes from the nomad-tasks role the same token also carries.
service "traefik-ingress" {
  policy = "write"
}
