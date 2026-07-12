# ── ACL policies owned by this module ────────────────────────────────────────
# The baseline Consul policies live in policies/ here because they're consumed
# only by this module: the anonymous attachment and the daemon tokens below both
# reference them, and nothing outside does. Same file-per-policy convention as
# the root policies.tf (name = filename minus .hcl); Consul stores rules verbatim
# so no chomp(). Adding a file adds a policy; make it a daemon token by listing
# it in var.daemon_token_policy_files.
resource "consul_acl_policy" "owned" {
  for_each = fileset("${path.module}/policies", "*.hcl")

  name  = trimsuffix(each.value, ".hcl")
  rules = file("${path.module}/policies/${each.value}")
}

# ── The anonymous token ──────────────────────────────────────────────────────
# Attaches the `anonymous` policy to Consul's built-in anonymous token (accessor
# 00000000-0000-0000-0000-000000000002) — what an unauthenticated request gets
# under default_policy = "deny". A policy *attachment* (rather than owning the
# token itself) leaves the built-in token in place and just asserts its policy
# set. Equivalent to `consul acl token update -accessor-id ...002 -policy-name
# anonymous`.
resource "consul_acl_token_policy_attachment" "anonymous" {
  token_id = "00000000-0000-0000-0000-000000000002"
  policy   = consul_acl_policy.owned[var.anonymous_policy_file].name
}

# ── The always-on daemon tokens ──────────────────────────────────────────────
# One Consul token per file in var.daemon_token_policy_files. These are daemon
# identities whose consumers read the token ONCE and never renew, so they must be
# plain, non-expiring Consul tokens (NOT leased/expiring — that's the
# Vault Consul secrets engine, for break-glass mgmt tokens). tofu owns them in
# state; each carries the like-named owned policy above, so token creation orders
# after it.
# Keyed on the policy name (filename minus .hcl), which is also the token
# description and its KV path below.
resource "consul_acl_token" "daemon" {
  for_each = { for f in var.daemon_token_policy_files : trimsuffix(f, ".hcl") => f }

  description = each.key
  policies    = [consul_acl_policy.owned[each.value].name]
}

# The token resource never exports its SecretID (only the accessor); fetch each
# one via the dedicated data source so it can be stashed in Vault KV below.
data "consul_acl_token_secret_id" "daemon" {
  for_each = consul_acl_token.daemon

  accessor_id = each.value.accessor_id
}

# ── Stash each token in Vault KV ─────────────────────────────────────────────
# The Ansible roles read these paths (kv/consul/tokens/<name>) to template each
# daemon's token into its config. Equivalent to a `vault kv put` per token.
#
# NOTE: the token secret_id lands in tofu state here (and in KV). Protect state.
resource "vault_kv_secret_v2" "daemon" {
  for_each = consul_acl_token.daemon

  mount     = var.kv_mount
  name      = "consul/tokens/${each.key}"
  data_json = jsonencode({ token = data.consul_acl_token_secret_id.daemon[each.key].secret_id })
}
