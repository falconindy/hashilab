# ── The JWT auth method ──────────────────────────────────────────────────────
# Nomad allocations log in to Consul with a signed JWT and get a short-lived,
# service-scoped token instead of sharing one static agent token. Replaces the
# `consul acl auth-method create -type jwt nomad-workloads` in
# bin/consul-build-nomad-wi. config_json embeds the home CA PEM so Consul can
# validate Nomad's HTTPS JWKS endpoint.
#
# ── max_token_ttl is deliberately OMITTED (no cap). Nomad manages the token's
# lifecycle by login (alloc start) / logout (alloc stop), NOT by renewal, so
# the token must live as long as the alloc — which runs indefinitely.  A finite
# cap silently kills every alloc's token at expiry: Connect sidecars lose their
# Envoy xDS stream ("16 unauthenticated: ACL not found"), Nomad-pushed TTL
# checks fail check/update, and logout hits an already-gone token. Do NOT tie
# this to the Nomad-side service_identity/task_identity ttl — that's the login
# JWT's lifetime, a different thing. Cleanup is handled by Nomad's logout.
#
# ── Ordering: this must exist BEFORE Nomad's consul{} gets the identity blocks.
# Nomad allocations begin their JWT login the moment those blocks deploy; if the
# method is missing, registration fails. So apply this first, then deploy the
# Nomad config change, verify, then flip Consul to default_policy=deny.
resource "consul_acl_auth_method" "nomad_workloads" {
  name        = var.auth_method_name
  type        = "jwt"
  description = "Login for Nomad workloads (workload identity)"

  config_json = jsonencode({
    JWKSURL          = var.nomad_jwks_url
    JWKSCACert       = file(var.home_ca_file)
    JWTSupportedAlgs = ["RS256"]
    BoundAudiences   = ["consul.io"]
    ClaimMappings = {
      nomad_namespace = "nomad_namespace"
      nomad_job_id    = "nomad_job_id"
      nomad_task      = "nomad_task"
      nomad_service   = "nomad_service"
    }
  })
}

# ── Service-bearing workloads -> per-service identity token ──────────────────
# Least privilege: a workload that exposes a service gets a Consul *service
# identity* token for exactly that service, so it can only register/represent
# its own service. bind_name interpolates Consul-side, so $${...} is escaped
# from tofu.
resource "consul_acl_binding_rule" "service" {
  auth_method = consul_acl_auth_method.nomad_workloads.name
  description = "nomad-workloads -> per-service identity"
  bind_type   = "service"
  bind_name   = "$${value.nomad_service}"
  selector    = "\"nomad_service\" in value"
}

# ── The nomad-tasks role ─────────────────────────────────────────────────────
# Serviceless tasks (no service block — they only read the catalog/KV from a
# `template` stanza) bind to this role. Its policy is created in policies.tf and
# passed in by reference so the role orders after the policy exists.
resource "consul_acl_role" "nomad_tasks" {
  name        = var.nomad_tasks_role_name
  description = "Nomad serviceless tasks"
  policies    = [var.nomad_tasks_policy_name]
}

# ── Serviceless tasks -> the nomad-tasks role ────────────────────────────────
resource "consul_acl_binding_rule" "tasks" {
  auth_method = consul_acl_auth_method.nomad_workloads.name
  description = "nomad-workloads -> nomad-tasks role"
  bind_type   = "role"
  bind_name   = consul_acl_role.nomad_tasks.name
  selector    = "\"nomad_service\" not in value"
}
