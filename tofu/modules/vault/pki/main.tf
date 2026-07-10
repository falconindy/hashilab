locals {
  issuing_certificates    = "{{cluster_aia_path}}/issuer/{{issuer_id}}/der"
  crl_distribution_points = "{{cluster_aia_path}}/issuer/{{issuer_id}}/crl/der"
  ocsp_servers            = "{{cluster_path}}/ocsp"
  cluster_path            = "${var.cluster_base}/v1/${var.backend}"
  aia_path                = "${coalesce(var.aia_base, var.cluster_base)}/v1/${var.backend}"
}

# ── The mount ────────────────────────────────────────────────────────────────
# Equivalent to: `vault secrets enable pki` + `vault secrets tune -max-lease-ttl=87600h`.
# No ACME on the root, so none of the pki_int header tuning here.
resource "vault_mount" "pki" {
  path                      = var.backend
  type                      = "pki"
  description               = "Self-signed root CA (home, 10-year TTL)."
  max_lease_ttl_seconds     = var.max_lease_ttl_seconds
  default_lease_ttl_seconds = 0
}

# ── The self-signed root ─────────────────────────────────────────────────────
# Equivalent to: `vault write pki/root/generate/internal ...`.
#
# One-shot cold-start ACTION that generates root key material. Gated behind
# `var.bootstrap` (default false) so a normal plan/apply can NEVER propose
# minting a new root — which would invalidate the CA bundle trusted on every
# node. Enable only on a green-field Vault; for an existing cluster leave false
# and import the mount/role/config (see README). The root cert itself isn't
# importable, and you never want to re-generate it, so it simply stays out of
# an existing-cluster plan.
resource "vault_pki_secret_backend_root_cert" "root" {
  count       = var.bootstrap ? 1 : 0
  backend     = vault_mount.pki.path
  type        = "internal" # private key stays in Vault, never exported
  common_name = var.common_name
  issuer_name = var.issuer_name
  ttl         = var.root_ttl
}

# ── Cluster + AIA config ─────────────────────────────────────────────────────
resource "vault_pki_secret_backend_config_cluster" "this" {
  backend  = vault_mount.pki.path
  path     = local.cluster_path
  aia_path = local.aia_path
}

resource "vault_pki_secret_backend_config_urls" "this" {
  backend                 = vault_mount.pki.path
  issuing_certificates    = [local.issuing_certificates]
  crl_distribution_points = [local.crl_distribution_points]
  ocsp_servers            = [local.ocsp_servers]
  enable_templating       = true

  depends_on = [vault_pki_secret_backend_root_cert.root]
}

# ── Issuing role ─────────────────────────────────────────────────────────────
# The `servers` role: allow_any_name, stored (no_store=false). Used to sign the
# intermediates and any direct server certs off the root.
resource "vault_pki_secret_backend_role" "servers" {
  backend        = vault_mount.pki.path
  name           = var.role_name
  allow_any_name = true
  no_store       = false

  depends_on = [vault_pki_secret_backend_root_cert.root]
}
