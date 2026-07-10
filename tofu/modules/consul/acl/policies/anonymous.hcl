# Attached to Consul's built-in anonymous token (accessor
# 00000000-0000-0000-0000-000000000002) by tofu (module.consul_acl). Under
# default_policy = "deny", this is what an unauthenticated request gets.
#
# Catalog + node read only — the minimum that keeps working WITHOUT a token:
#   - Consul DNS (CoreDNS forwards *.service.home to :8600, which honors ACLs;
#     no service read here means empty DNS cluster-wide)
#   - the browser dashboard (www/homelabdash polls /v1/catalog + /v1/health)
#   - Prometheus consul_sd target discovery
#
# Deliberately NO key_prefix (the mesh stores nothing in Consul KV) and no
# write anywhere: the blast radius is read-only recon by anyone who can reach
# :8501 or Consul DNS. Tighten if that exposure ever becomes unacceptable.
node_prefix "" {
  policy = "read"
}

service_prefix "" {
  policy = "read"
}
