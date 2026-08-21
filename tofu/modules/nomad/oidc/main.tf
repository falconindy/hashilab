locals {
  redirect_uris = [
    "${var.nomad_address}/ui/settings/tokens",
    "http://localhost:4649/oidc/callback",
  ]
}

# The OIDC client secret lives in Vault KV (pre-existing: kv/pocket-id/nomad)
# instead of a hand-edited tfvars file. Unlike vault_jwt_auth_backend in
# modules/vault/oidc, the hashicorp/nomad provider's nomad_acl_auth_method has
# no oidc_client_secret_wo counterpart yet, so this has to be a normal
# (non-ephemeral) data source — the secret still lands in tofu state here,
# same as it did when it came from a var. `tofu validate` nags that this data
# source is deprecated in favor of the ephemeral resource — that's the
# provider itself confirming the gap; it's expected until
# nomad_acl_auth_method grows a write-only attribute. Switch this to an
# ephemeral read + write-only attribute once the provider adds one.
data "vault_kv_secret_v2" "oidc" {
  mount = "kv"
  name  = "pocket-id/nomad"
}

# ── The OIDC auth method ─────────────────────────────────────────────────────
# Equivalent to `nomad acl auth-method create/update -type=OIDC ... pocket-id`.
# No key material — pure config, so no bootstrap gate (like the Vault OIDC
# module). Needs a Nomad *management* token to apply (see providers.tf).
resource "nomad_acl_auth_method" "pocket_id" {
  name              = "pocket-id"
  type              = "OIDC"
  token_locality    = "global"
  max_token_ttl     = "20h"
  default           = true
  token_name_format = "$${auth_method_name}-$${value.user}"

  config {
    oidc_discovery_url    = var.oidc_discovery_url
    oidc_client_id        = var.oidc_client_id
    oidc_client_secret    = data.vault_kv_secret_v2.oidc.data["oidc_client_secret"]
    oidc_scopes           = ["openid", "profile"]
    oidc_enable_pkce      = true
    bound_audiences       = [var.oidc_client_id]
    claim_mappings        = { preferred_username = "user" }
    allowed_redirect_uris = local.redirect_uris
  }
}

# ── The binding rule ─────────────────────────────────────────────────────────
# Equivalent to `nomad acl binding-rule create -bind-type=policy -bind-name=admin`.
# No selector: everyone who authenticates through the (group-gated) Pocket-ID
# client is bound to the admin policy.
resource "nomad_acl_binding_rule" "admin" {
  auth_method = nomad_acl_auth_method.pocket_id.name
  description = "pocket-id -> admin policy"
  bind_type   = "policy"
  bind_name   = "admin"
}
