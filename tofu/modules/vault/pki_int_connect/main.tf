# The Vault side of Consul Connect's CA. Unlike pki_int / pki_int_internal, this
# module does NOT run the CSR → root-sign → import chain: Consul's Vault CA
# provider generates the intermediate itself, has the root sign it, and rotates
# every mesh leaf cert directly against Vault. So there's no key material born in
# tofu here (hence no `bootstrap` gate) — the module only reserves the mount and
# grants Consul a least-privilege, auto-renewing credential to drive it.

# ── The intermediate mount ───────────────────────────────────────────────────
# Empty pki mount Consul fills with the intermediate it generates + gets the root
# to sign. max_lease_ttl_seconds sets only the initial bound at create; on every
# configure Consul TUNES this mount's max_lease_ttl to its own IntermediateCertTTL
# (default 8760h/1y), so Consul owns the field thereafter — we ignore_changes on it
# rather than re-asserting our value and fighting Consul on every plan.
resource "vault_mount" "pki_int_connect" {
  path                      = var.backend
  type                      = "pki"
  description               = "Intermediate CA for Consul Connect mesh mTLS (generated + rotated by Consul)."
  max_lease_ttl_seconds     = var.max_lease_ttl_seconds
  default_lease_ttl_seconds = 0

  lifecycle {
    ignore_changes = [max_lease_ttl_seconds]
  }
}

# ── The provider policy (module-owned) ───────────────────────────────────────
# Least-privilege per HashiCorp's Vault CA provider guide, scoped to our root
# (pki) and this intermediate. Colocated in policies/ like every other
# single-consumer policy in the repo; chomp() to match Vault stripping trailing
# whitespace.
resource "vault_policy" "connect_ca" {
  name   = var.policy_name
  policy = chomp(file("${path.module}/policies/consul-connect-ca.hcl"))
}

# ── The keyless AppRole role ─────────────────────────────────────────────────
# A dedicated role on the existing approle mount (var.approle_backend, enabled by
# module.vault_approle). Keyless like the vault-agent role — role_id alone
# (bind_secret_id=false), CIDR-bound to the Consul servers — so Consul's
# ca_config auth_method passes only role_id. token_type=service so the CA
# provider can renew it (batch tokens can't self-renew).
resource "vault_approle_auth_backend_role" "connect_ca" {
  backend        = var.approle_backend
  role_name      = var.approle_role_name
  token_policies = [vault_policy.connect_ca.name]

  bind_secret_id    = false
  token_bound_cidrs = var.server_cidrs
  token_ttl         = var.token_ttl_seconds
  token_type        = "service"
}

# ── Stash role_id in Vault KV ────────────────────────────────────────────────
# The consul role reads kv/consul/connect-ca to template role_id into servers'
# connect.ca_config auth_method — same KV-stash + controller-side-lookup path the
# daemon tokens use (module.consul_acl). role_id isn't a high-value secret, but
# sourcing it from KV keeps tofu the source of truth (it mints role_id) rather
# than hardcoding it in an Ansible var. Equivalent to a `vault kv put`.
resource "vault_kv_secret_v2" "role_id" {
  mount     = var.kv_mount
  name      = "consul/connect-ca"
  data_json = jsonencode({ role_id = vault_approle_auth_backend_role.connect_ca.role_id })
}
