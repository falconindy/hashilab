locals {
  redirect_uris = concat([
    "${var.nomad_address}/ui/settings/tokens",
    "http://localhost:4649/oidc/callback",
  ], var.extra_redirect_uris)
}

# ── The OIDC auth method ─────────────────────────────────────────────────────
# Replaces `nomad acl auth-method create/update -type=OIDC ... pocket-id`.
# No key material — pure config, so no bootstrap gate (like the Vault OIDC
# module). Needs a Nomad *management* token to apply (see providers.tf).
resource "nomad_acl_auth_method" "pocket_id" {
  name              = var.auth_method_name
  type              = "OIDC"
  token_locality    = var.token_locality
  max_token_ttl     = var.max_token_ttl
  default           = var.is_default
  token_name_format = var.token_name_format

  config {
    oidc_discovery_url    = var.oidc_discovery_url
    oidc_client_id        = var.oidc_client_id
    oidc_client_secret    = var.oidc_client_secret
    oidc_scopes           = var.oidc_scopes
    oidc_enable_pkce      = var.oidc_enable_pkce
    bound_audiences       = [var.oidc_client_id]
    claim_mappings        = var.claim_mappings
    allowed_redirect_uris = local.redirect_uris
  }
}

# ── The binding rule ─────────────────────────────────────────────────────────
# Replaces `nomad acl binding-rule create -bind-type=policy -bind-name=admin`.
# No selector: everyone who authenticates through the (group-gated) Pocket-ID
# client is bound to the admin policy.
resource "nomad_acl_binding_rule" "admin" {
  auth_method = nomad_acl_auth_method.pocket_id.name
  description = "pocket-id -> admin policy"
  bind_type   = "policy"
  bind_name   = var.bind_policy_name
}
