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
# Equivalent to: `vault secrets enable -path=pki_int pki`.
resource "vault_mount" "pki_int" {
  path                      = "pki_int"
  type                      = "pki"
  description               = "Intermediate CA; issues the *.service.home wildcard for Traefik."
  max_lease_ttl_seconds     = 157680000 # 5y
  default_lease_ttl_seconds = 0
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
# The mount's only role. The internal Traefik job issues its own
# *.service.home wildcard via pkiCert (Nomad WI role `traefik`) rather than
# through ACME: two instances behind one round-robin name can't reliably
# answer each other's http-01 challenges. Scoped to service.home since a
# workload token is all that gates issuance. issuer_ref is left at the
# backend default (the imported intermediate). no_store because every alloc
# start and every renewal mints a fresh cert; nothing ever revokes them.
# 100d because Nomad's pkiCert re-issues at a fixed 90% of lifetime: this
# puts renewal ~10d before expiry (45d would leave only ~4.5d to fix a
# broken renewal).
resource "vault_pki_secret_backend_role" "traefik" {
  backend = vault_mount.pki_int.path
  name    = "traefik"

  allowed_domains             = ["service.home"]
  allow_subdomains            = true
  allow_wildcard_certificates = true
  allow_bare_domains          = false
  allow_localhost             = false
  allow_ip_sans               = false
  server_flag                 = true
  client_flag                 = false

  # Matches what Traefik's ACME client generated.
  key_type = "rsa"
  key_bits = 4096

  ttl      = 8640000 # 100d
  max_ttl  = 8640000 # 100d
  no_store = true

  depends_on = [vault_pki_secret_backend_intermediate_set_signed.import]
}

# ── ACME (disabled) ──────────────────────────────────────────────────────────
# Traefik used to issue through ACME here; nothing does now. Kept as a resource
# rather than deleted because the provider's Delete is a no-op — dropping it
# would leave ACME enabled in Vault and merely forget it. forbid as a second
# lock in case it's ever re-enabled without a deliberate policy.
resource "vault_pki_secret_backend_config_acme" "this" {
  backend                  = vault_mount.pki_int.path
  enabled                  = false
  default_directory_policy = "forbid"
}

# ── Auto-tidy ────────────────────────────────────────────────────────────────
# The provider always writes every boolean field on apply (unset = false), so
# every tidy operation that should stay on must be listed explicitly here.
resource "vault_pki_secret_backend_config_auto_tidy" "this" {
  backend = vault_mount.pki_int.path
  enabled = true

  tidy_cert_store                       = true
  tidy_revoked_certs                    = true
  tidy_acme                             = true # reaps leftover ACME accounts/orders
  tidy_revoked_cert_issuer_associations = true

  # No-ops on OSS/non-replicated Vault, but part of HashiCorp's recommended
  # baseline (`vault pki health-check`'s enable_auto_tidy check).
  tidy_revocation_queue            = true
  tidy_cross_cluster_revoked_certs = true
}
