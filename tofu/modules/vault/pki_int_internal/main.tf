locals {
  issuing_certificates    = "{{cluster_aia_path}}/issuer/{{issuer_id}}/der"
  crl_distribution_points = "{{cluster_aia_path}}/issuer/{{issuer_id}}/crl/der"
  ocsp_servers            = "{{cluster_path}}/ocsp"
  cluster_path            = "${var.cluster_base}/v1/${var.backend}"
  aia_path                = "${coalesce(var.aia_base, var.cluster_base)}/v1/${var.backend}"
}

# ── The mount ────────────────────────────────────────────────────────────────
# Replaces: `vault secrets enable -path=pki_int_internal pki` + the ttl tune.
# No ACME on this engine, so none of the pki_int header tuning here.
resource "vault_mount" "pki_int_internal" {
  path                      = var.backend
  type                      = "pki"
  description               = "Intermediate CA for internal client certs (no ACME, no storage)."
  max_lease_ttl_seconds     = var.max_lease_ttl_seconds
  default_lease_ttl_seconds = 0
}

# ── Intermediate CSR → root signs it → import the signed cert ────────────────
# Same one-shot, key-generating chain as pki_int, gated behind var.bootstrap
# (default false). See the pki_int module / README for the full rationale.
resource "vault_pki_secret_backend_intermediate_cert_request" "csr" {
  count       = var.bootstrap ? 1 : 0
  backend     = vault_mount.pki_int_internal.path
  type        = "internal" # private key stays in Vault, never exported
  common_name = var.common_name
}

resource "vault_pki_secret_backend_root_sign_intermediate" "signed" {
  count       = var.bootstrap ? 1 : 0
  backend     = var.root_backend
  csr         = vault_pki_secret_backend_intermediate_cert_request.csr[0].csr
  common_name = var.common_name
  issuer_ref  = var.root_issuer_ref
  format      = "pem_bundle"
  ttl         = var.intermediate_sign_ttl
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
  name           = var.role_name
  allow_any_name = true
  max_ttl        = var.role_max_ttl_seconds
  no_store       = true

  depends_on = [vault_pki_secret_backend_intermediate_set_signed.import]
}
