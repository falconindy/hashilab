# ── The dedicated Consul management token ────────────────────────────────────
# The engine authenticates to Consul with its own dedicated management token
# rather than the bootstrap token, so the bootstrap token can be retired
# afterwards without killing the engine. Consul has no `type=management` on a
# token — "management" is the built-in `global-management` policy attached to it.
# tofu owns exactly one token in state, so rotation and pruning are automatic:
# re-applying with a change rotates it and the superseded one is deleted.
# Creating this requires CONSUL_HTTP_TOKEN to be a *management* token (see
# providers.tf).
#
# NOTE: secret_id lands in tofu state. Protect state (see versions.tf).
resource "consul_acl_token" "engine" {
  description = var.engine_token_name
  policies    = ["global-management"]
}

# The token resource never exports its SecretID (only the accessor); fetch it via
# the dedicated data source so it can be written into consul/config/access.
data "consul_acl_token_secret_id" "engine" {
  accessor_id = consul_acl_token.engine.accessor_id
}

# ── The secrets engine ───────────────────────────────────────────────────────
# Replaces `vault secrets enable consul` + `vault write consul/config/access`.
# The engine authenticates to Consul with the dedicated token above — NOT the
# bootstrap token. `scheme=https` relies on the Vault servers trusting the home
# CA via their OS trust store (same as the Nomad engine's https config).
resource "vault_consul_secret_backend" "consul" {
  path        = var.backend
  address     = var.consul_address
  scheme      = var.scheme
  token       = data.consul_acl_token_secret_id.engine.secret_id
  description = "Mints short-lived, lease-bound Consul management tokens on demand."
}

# ── The mgmt role ────────────────────────────────────────────────────────────
# `vault read consul/creds/mgmt` mints a client token carrying the built-in
# `global-management` policy — the break-glass path for Consul ACL administration
# (creating tokens/policies/auth-methods/binding-rules), which no lesser policy
# can grant. Consumed by bin/consul-mgmt. (This is the modern equivalent of the
# script's `token_type=management`; legacy management tokens are deprecated in
# Consul 1.11+, so we attach global-management instead.)
resource "vault_consul_secret_backend_role" "mgmt" {
  backend         = vault_consul_secret_backend.consul.path
  name            = var.role_name
  consul_policies = ["global-management"]
}
