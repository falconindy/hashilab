# ── The auth method ──────────────────────────────────────────────────────────
# The approle backend vault-agent authenticates against. No key material — pure
# config, so no bootstrap gate.
resource "vault_auth_backend" "approle" {
  type = "approle"
  path = var.backend
}

# ── Policies owned by this module ────────────────────────────────────────────
# Colocated in policies/ because they're an implementation detail of this approle
# and nothing outside references them (internal-server-certs — vault-agent renders
# TLS from pki_int_internal, which it grants). A caller opts in by filename via
# var.owned_policy_files; external policy names still come via token_policies.
# chomp() to match Vault stripping trailing whitespace.
resource "vault_policy" "owned" {
  for_each = fileset("${path.module}/policies", "*.hcl")

  name   = trimsuffix(each.value, ".hcl")
  policy = chomp(file("${path.module}/policies/${each.value}"))
}

# ── The vault-agent role ─────────────────────────────────────────────────────
# vault-agent logs in with role_id alone (bind_secret_id=false) and gets a token
# carrying token_policies, which it uses to render TLS certs on each host. The
# role_id is stable and shipped to hosts as a static file out of band; import
# this role so tofu adopts the existing role_id rather than minting a new one.
resource "vault_approle_auth_backend_role" "this" {
  backend   = vault_auth_backend.approle.path
  role_name = var.role_name
  token_policies = concat(
    var.token_policies,
    [for f in var.owned_policy_files : vault_policy.owned[f].name],
  )
  bind_secret_id = var.bind_secret_id

  secret_id_bound_cidrs = var.secret_id_bound_cidrs
  token_bound_cidrs     = var.token_bound_cidrs
  token_ttl             = var.token_ttl_seconds
  token_max_ttl         = var.token_max_ttl_seconds
  token_type            = var.token_type
}
