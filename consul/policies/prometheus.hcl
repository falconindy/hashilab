# Bound (via the `prometheus` Consul role + a job-scoped nomad-workloads binding
# rule, module.consul_nomad_wi) to the Prometheus TASK workload identity.
# Prometheus scrapes Consul's own telemetry at /v1/agent/metrics, which requires
# agent:read — not covered by the read-only nomad-tasks role its task token
# otherwise carries, nor by the anonymous token under default_policy = "deny".
# This adds exactly that read so the `consul` scrape job keeps reporting.
#
# agent:read is per-node agent introspection (metrics, self, members); no
# catalog/service grant here — that comes from the nomad-tasks role the same
# token also carries.
agent_prefix "" {
  policy = "read"
}
