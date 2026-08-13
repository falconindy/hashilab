locals {
  issuing_certificates    = "{{cluster_aia_path}}/issuer/{{issuer_id}}/der"
  crl_distribution_points = "{{cluster_aia_path}}/issuer/{{issuer_id}}/crl/der"
  ocsp_servers            = "{{cluster_path}}/ocsp"
  cluster_path            = "${var.cluster_base}/v1/pki_int_internal"
  aia_path                = "${coalesce(var.aia_base, var.cluster_base)}/v1/pki_int_internal"
}

# ── The mount ────────────────────────────────────────────────────────────────
# Equivalent to: `vault secrets enable -path=pki_int_internal pki` + the ttl tune.
# No ACME on this engine, so none of the pki_int header tuning here.
resource "vault_mount" "pki_int_internal" {
  path                      = "pki_int_internal"
  type                      = "pki"
  description               = "Intermediate CA for internal client certs (no ACME, no storage)."
  max_lease_ttl_seconds     = 157680000 # 43800h
  default_lease_ttl_seconds = 0
}

# ── Intermediate CSR → root signs it → import the signed cert ────────────────
# Same one-shot, key-generating chain as pki_int, gated behind var.bootstrap
# (default false). See the pki_int module / README for the full rationale.
resource "vault_pki_secret_backend_intermediate_cert_request" "csr" {
  count       = var.bootstrap ? 1 : 0
  backend     = vault_mount.pki_int_internal.path
  type        = "internal" # private key stays in Vault, never exported
  common_name = "home Vault Intermediate Authority [Internal]"
}

resource "vault_pki_secret_backend_root_sign_intermediate" "signed" {
  count       = var.bootstrap ? 1 : 0
  backend     = var.root_backend
  csr         = vault_pki_secret_backend_intermediate_cert_request.csr[0].csr
  common_name = "home Vault Intermediate Authority [Internal]"
  issuer_ref  = var.root_issuer_ref
  format      = "pem_bundle"
  ttl         = "43800h"
}

resource "vault_pki_secret_backend_intermediate_set_signed" "import" {
  count       = var.bootstrap ? 1 : 0
  backend     = vault_mount.pki_int_internal.path
  certificate = vault_pki_secret_backend_root_sign_intermediate.signed[0].certificate
}

# ── Cluster + AIA config ─────────────────────────────────────────────────────
resource "vault_pki_secret_backend_config_cluster" "this" {
  backend  = vault_mount.pki_int_internal.path
  path     = local.cluster_path
  aia_path = local.aia_path
}

resource "vault_pki_secret_backend_config_urls" "this" {
  backend                 = vault_mount.pki_int_internal.path
  issuing_certificates    = [local.issuing_certificates]
  crl_distribution_points = [local.crl_distribution_points]
  ocsp_servers            = [local.ocsp_servers]
  enable_templating       = true

  depends_on = [vault_pki_secret_backend_intermediate_set_signed.import]
}

# ── Issuing role ─────────────────────────────────────────────────────────────
# no_store=true: internal client certs are ephemeral and not persisted by Vault.
resource "vault_pki_secret_backend_role" "intermediate" {
  backend        = vault_mount.pki_int_internal.path
  name           = "intermediate"
  allow_any_name = true
  max_ttl        = 15768000 # 4380h
  no_store       = true

  depends_on = [vault_pki_secret_backend_intermediate_set_signed.import]
}

# ── Auto-tidy ────────────────────────────────────────────────────────────────
# The provider always writes every boolean field on apply (unset = false), so
# every tidy operation that should stay on must be listed explicitly here.
resource "vault_pki_secret_backend_config_auto_tidy" "this" {
  backend = vault_mount.pki_int_internal.path
  enabled = true

  tidy_cert_store                       = true
  tidy_revoked_certs                    = true
  tidy_acme                             = true
  tidy_revoked_cert_issuer_associations = true

  # No-ops on OSS/non-replicated Vault, but part of HashiCorp's recommended
  # baseline (`vault pki health-check`'s enable_auto_tidy check).
  tidy_revocation_queue            = true
  tidy_cross_cluster_revoked_certs = true
}
