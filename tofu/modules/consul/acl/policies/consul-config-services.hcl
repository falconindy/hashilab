# Set as acl.tokens.config_file_service_registration on every agent (the consul
# and synology roles read it from Vault KV, where module.consul_acl stashes it).
# Authorizes registration of services defined in agent config FILES — distinct
# from the agent token (node anti-entropy) and from Nomad workload identity
# (which carries its own token). Under default_policy = "deny", config-file
# service registration falls back to this token, then the anonymous token; the
# anonymous policy is read-only, so without this the nas service silently stop
# registering.
#
# service:write is required for EVERY config-file service on any node:
#   - nas           — the NAS only
# Named rather than service_prefix "" write to keep the blast radius tight (cf.
# anonymous.hcl): add a service here when a new one is defined in a *.hcl config.
service "nas" {
  policy = "write"
}

service "node-exporter" {
  policy = "write"
}
