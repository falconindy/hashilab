# ── The anonymous token ──────────────────────────────────────────────────────
# Attaches the `anonymous` policy to Consul's built-in anonymous token (accessor
# 00000000-0000-0000-0000-000000000002) — what an unauthenticated request gets
# under default_policy = "deny". A policy *attachment* (rather than owning the
# token itself) leaves the built-in token in place and just asserts its policy
# set. Replaces `consul acl token update -accessor-id ...002 -policy-name
# anonymous` from bin/consul-build-acl-base.
resource "consul_acl_token_policy_attachment" "anonymous" {
  token_id = "00000000-0000-0000-0000-000000000002"
  policy   = var.anonymous_policy_name
}

# ── The always-on daemon tokens ──────────────────────────────────────────────
# consul-agent, nomad-agent and vault-registration are daemon identities whose
# consumers read the token ONCE and never renew, so they must be plain,
# non-expiring Consul tokens (NOT leased/expiring — that's the Vault Consul
# secrets engine, for break-glass mgmt tokens). tofu owns them in state; the
# policy each carries is created in policies.tf and passed in by reference, so
# token creation orders after the policy exists.
resource "consul_acl_token" "daemon" {
  for_each = var.daemon_policy_names

  description = each.key
  policies    = [each.value]
}

# The token resource never exports its SecretID (only the accessor); fetch each
# one via the dedicated data source so it can be stashed in Vault KV below.
data "consul_acl_token_secret_id" "daemon" {
  for_each = var.daemon_policy_names

  accessor_id = consul_acl_token.daemon[each.key].accessor_id
}

# ── Stash each token in Vault KV ─────────────────────────────────────────────
# The Ansible roles read these paths (kv/consul/tokens/<name>) to template the
# tokens into config: the consul role's `consul acl set-agent-token agent`, the
# nomad role's consul{} token, and Vault's service_registration token. Replaces
# the `vault kv put` calls in bin/consul-build-acl-base.
#
# NOTE: the token secret_id lands in tofu state here (and in KV). Protect state.
resource "vault_kv_secret_v2" "daemon" {
  for_each = var.daemon_policy_names

  mount     = var.kv_mount
  name      = "consul/tokens/${each.key}"
  data_json = jsonencode({ token = data.consul_acl_token_secret_id.daemon[each.key].secret_id })
}
