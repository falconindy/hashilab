locals {
  # The two callbacks: the Vault UI login and the CLI's localhost listener. These
  # must also exist on the Pocket-ID client's redirect allow-list, or the browser
  # round-trip fails.
  redirect_uris = [
    "${var.vault_address}/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8250/oidc/callback",
  ]
}

# ── The auth method ──────────────────────────────────────────────────────────
# Equivalent to: `vault auth enable oidc` + `vault write auth/oidc/config ...`.
# No key material here — pure config, fully idempotent, so unlike the PKI/SSH
# modules there's no bootstrap gate.
resource "vault_jwt_auth_backend" "oidc" {
  type               = "oidc"
  path               = "oidc"
  description        = "Pocket-ID OIDC login (passkey) — issues admin tokens without carrying the root token."
  oidc_discovery_url = var.oidc_discovery_url
  oidc_client_id     = var.oidc_client_id
  oidc_client_secret = var.oidc_client_secret

  # Lets `vault login -method=oidc` work without naming a role.
  default_role = "admin"
}

# ── The role ─────────────────────────────────────────────────────────────────
# Equivalent to: `vault write auth/oidc/role/admin ...`. Every user who authenticates
# through the Pocket-ID client gets token_policies.
resource "vault_jwt_auth_backend_role" "role" {
  backend               = vault_jwt_auth_backend.oidc.path
  role_name             = "admin"
  role_type             = "oidc"
  user_claim            = "email"
  oidc_scopes           = ["profile", "email"]
  allowed_redirect_uris = local.redirect_uris
  token_policies        = ["admin"]
  token_ttl             = 72000 # 20h
  token_max_ttl         = 72000 # 20h
}
