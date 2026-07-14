# ── The JWT auth method ──────────────────────────────────────────────────────
# Nomad allocations log in to Consul with a signed JWT and get a short-lived,
# service-scoped token instead of sharing one static agent token. Equivalent to
# `consul acl auth-method create -type jwt nomad-workloads`. config_json embeds
# the home CA PEM so Consul can validate Nomad's HTTPS JWKS endpoint.
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

# ── Every service workload also gets agent:read (Envoy bootstrap) ────────────
# Nomad boots each Connect sidecar with `consul connect envoy -bootstrap`, run
# with the service-identity token above; that command probes /v1/agent/self
# (needs agent:read). The service identity doesn't include agent:read, so union
# it in via an additive role — binding rules union, so a service token ends up
# service-identity ∪ connect-agent-read. Same selector as the service rule so it
# tracks exactly the service-bearing workloads and never a serviceless task.
resource "consul_acl_role" "connect_agent_read" {
  name        = "connect-agent-read"
  description = "agent:read for service workloads (Envoy bootstrap probes /v1/agent/self)"
  policies    = [consul_acl_policy.owned["connect-agent-read.hcl"].name]
}

resource "consul_acl_binding_rule" "connect_agent_read" {
  auth_method = consul_acl_auth_method.nomad_workloads.name
  description = "nomad-workloads -> connect-agent-read role (service workloads)"
  bind_type   = "role"
  bind_name   = consul_acl_role.connect_agent_read.name
  selector    = "\"nomad_service\" in value"
}

# ── ACL policies owned by this module ────────────────────────────────────────
# The workload policies these roles attach (nomad-tasks + the task-identity ones:
# traefik, traefik-ingress, prometheus) live in policies/ here because this module
# is their only consumer — it creates both the policies and the roles/binding
# rules that grant them. Same file-per-policy convention as the root policies.tf
# (name = filename minus .hcl); Consul stores rules verbatim so no chomp().
resource "consul_acl_policy" "owned" {
  for_each = fileset("${path.module}/policies", "*.hcl")

  name  = trimsuffix(each.value, ".hcl")
  rules = file("${path.module}/policies/${each.value}")
}

# ── The nomad-tasks role ─────────────────────────────────────────────────────
# Serviceless tasks (no service block — they only read the catalog/KV from a
# `template` stanza) bind to this role. Its policy is module-owned (above), keyed
# by filename, so the role orders after the policy exists.
resource "consul_acl_role" "nomad_tasks" {
  name        = var.nomad_tasks_role_name
  description = "Nomad serviceless tasks"
  policies    = [consul_acl_policy.owned[var.nomad_tasks_policy_file].name]
}

# ── Serviceless tasks -> the nomad-tasks role ────────────────────────────────
resource "consul_acl_binding_rule" "tasks" {
  auth_method = consul_acl_auth_method.nomad_workloads.name
  description = "nomad-workloads -> nomad-tasks role"
  bind_type   = "role"
  bind_name   = consul_acl_role.nomad_tasks.name
  selector    = "\"nomad_service\" not in value"
}

# ── Extra roles for specific task identities (var.task_identity_roles) ────────
# A handful of workloads need more from Consul than the read-only nomad-tasks
# role their task token carries by default, but they authenticate as *task*
# identities (no nomad_service claim), so they can't get a service identity:
#   - the connectaware Traefik ingresses fetch a Connect leaf cert for their own
#     service (/v1/agent/connect/ca/leaf/<svc>, needs service:write on it);
#   - Prometheus scrapes Consul's /v1/agent/metrics (needs agent:read).
# Each entry gets a role (carrying the caller-supplied policy) plus an additive
# binding rule keyed on the caller's selector. Binding rules union, so the token
# ends up with nomad-tasks ∪ this role; the caller's selector carries the
# "nomad_service" not in value guard so this never touches a service identity.
resource "consul_acl_role" "task_identity" {
  for_each = var.task_identity_roles

  name        = each.key
  description = "Extra grants for the ${each.key} task identity"
  policies    = [consul_acl_policy.owned[each.value.policy_file].name]
}

resource "consul_acl_binding_rule" "task_identity" {
  for_each = var.task_identity_roles

  auth_method = consul_acl_auth_method.nomad_workloads.name
  description = "nomad-workloads -> ${each.key} role (task identity)"
  bind_type   = "role"
  bind_name   = consul_acl_role.task_identity[each.key].name
  selector    = each.value.selector
}
