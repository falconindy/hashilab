locals {
  # AIA templating strings, encoded verbatim into config/urls with
  # enable_templating=true so Vault substitutes per-issuer at issue time.
  issuing_certificates    = "{{cluster_aia_path}}/issuer/{{issuer_id}}/der"
  crl_distribution_points = "{{cluster_aia_path}}/issuer/{{issuer_id}}/crl/der"
  ocsp_servers            = "{{cluster_path}}/ocsp"
  cluster_path            = "${var.cluster_base}/v1/pki_int"
  aia_path                = "${coalesce(var.aia_base, var.cluster_base)}/v1/pki_int"
}

# ── The mount ────────────────────────────────────────────────────────────────
# Equivalent to: `vault secrets enable -path=pki_int pki` + the ACME header `tune`.
resource "vault_mount" "pki_int" {
  path                      = "pki_int"
  type                      = "pki"
  description               = "Intermediate CA with ACME enabled; issues *.service.home certs for Traefik."
  max_lease_ttl_seconds     = 157680000 # 43800h
  default_lease_ttl_seconds = 0

  # ACME needs these headers to pass through the mount barrier.
  passthrough_request_headers = ["If-Modified-Since"]
  allowed_response_headers = [
    "Last-Modified",
    "Location",
    "Replay-Nonce",
    "Link",
  ]
}

# ── Intermediate CSR → root signs it → import the signed cert ────────────────
# These three model a one-shot cold-start ACTION, not readable state, and they
# generate CA key material inside Vault. Gated behind `var.bootstrap` (default
# false) so a normal plan/apply NEVER proposes re-signing an existing
# intermediate. Enable only on a green-field mount; for an existing cluster
# leave false and `tofu import` the mount/role/config (see README).
resource "vault_pki_secret_backend_intermediate_cert_request" "csr" {
  count       = var.bootstrap ? 1 : 0
  backend     = vault_mount.pki_int.path
  type        = "internal" # private key stays in Vault, never exported
  common_name = "home Vault Intermediate Authority"
}

resource "vault_pki_secret_backend_root_sign_intermediate" "signed" {
  count       = var.bootstrap ? 1 : 0
  backend     = var.root_backend
  csr         = vault_pki_secret_backend_intermediate_cert_request.csr[0].csr
  common_name = "home Vault Intermediate Authority"
  issuer_ref  = var.root_issuer_ref
  format      = "pem_bundle"
  ttl         = "43800h"
}

resource "vault_pki_secret_backend_intermediate_set_signed" "import" {
  count       = var.bootstrap ? 1 : 0
  backend     = vault_mount.pki_int.path
  certificate = vault_pki_secret_backend_root_sign_intermediate.signed[0].certificate
}

# ── Cluster + AIA config ─────────────────────────────────────────────────────
resource "vault_pki_secret_backend_config_cluster" "this" {
  backend  = vault_mount.pki_int.path
  path     = local.cluster_path
  aia_path = local.aia_path
}

resource "vault_pki_secret_backend_config_urls" "this" {
  backend                 = vault_mount.pki_int.path
  issuing_certificates    = [local.issuing_certificates]
  crl_distribution_points = [local.crl_distribution_points]
  ocsp_servers            = [local.ocsp_servers]
  enable_templating       = true

  # config/urls is only meaningful once the signed intermediate is in place.
  depends_on = [vault_pki_secret_backend_intermediate_set_signed.import]
}

# ── Issuing role ─────────────────────────────────────────────────────────────
# issuer_ref is left at the backend default, which is the intermediate we just
# imported (equivalent to `vault read -field=default .../config/issuers`).
resource "vault_pki_secret_backend_role" "intermediate" {
  backend        = vault_mount.pki_int.path
  name           = "intermediate"
  allow_any_name = true
  max_ttl        = 2764800 # 768h
  no_store       = false

  depends_on = [vault_pki_secret_backend_intermediate_set_signed.import]
}

# ── ACME ─────────────────────────────────────────────────────────────────────
resource "vault_pki_secret_backend_config_acme" "this" {
  backend = vault_mount.pki_int.path
  enabled = true

  depends_on = [
    vault_pki_secret_backend_config_cluster.this,
    vault_pki_secret_backend_config_urls.this,
  ]
}
