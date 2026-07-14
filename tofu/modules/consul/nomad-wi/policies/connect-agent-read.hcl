# Attached (via the connect-agent-read role) to EVERY service-bearing Nomad
# workload, on top of its per-service identity. REQUIRED IN THIS CLUSTER — not a
# cosmetic log-noise fix; do not revert while 8502 is disabled (see below).
#
# Nomad boots each Connect sidecar by shelling out `consul connect envoy
# -bootstrap` with the workload's *service-identity* token. That command's
# xdsAddress() -> lookupXdsPort() probes /v1/agent/self (agent:read) to discover
# the agent's real xDS/gRPC port. Consul deliberately swallows a denial here as a
# "UX optimization" and falls back to a HARDCODED default of 8502 — which we
# disable. So under `default_policy = deny`, a service identity (service:write +
# catalog read, but NOT agent:read) gets denied, falls back to 8502, and the
# generated bootstrap aims Envoy's xDS/ADS stream at a dead port: the sidecar
# never gets its config. This unions agent:read in so the probe succeeds and the
# real port is discovered.
#
# agent:read is read-only per-node introspection (self/metrics/members): no
# mutation, no service:write. Same grant prometheus.hcl carries for /v1/agent/
# metrics; here it rides on the service-identity path instead of a task identity.
agent_prefix "" {
  policy = "read"
}
