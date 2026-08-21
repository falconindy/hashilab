# Single source of truth for values shared across modules. Terraform locals and
# variables do NOT cross module boundaries, so each module still declares its own
# input (that's module encapsulation) — but the *value* lives here once and is
# passed in explicitly below, instead of repeating the literal in every block.
#
# Note these are cluster *data* (baked into issued-cert URLs and OIDC redirect
# URIs), not provider connection config — the vault/nomad providers still read
# VAULT_ADDR / NOMAD_ADDR from the environment (see providers.tf).
locals {
  vault_address      = "https://vault.service.home:8200"
  nomad_address      = "https://nomad.service.home:4646"
  oidc_discovery_url = "https://id.falconindy.com"

  # Pocket-ID OIDC client IDs — two separate clients, one per consumer. Not
  # secret (the client *secrets* live in Vault KV and are read at plan/apply
  # time — see modules/vault/oidc, modules/nomad/oidc, and tofu/README.md).
  vault_oidc_client_id = "9531992a-e09e-4b48-bc10-887b89790692"
  nomad_oidc_client_id = "4b0f71ba-1833-4bfe-b2e7-a2d90f3ac1dc"

  # Consul HTTP API as host:port (no scheme) — the Vault Consul secrets engine
  # wants address + scheme split (see module.vault_consul).
  consul_address = "consul.service.home:8501"

  # Nomad's JWKS endpoint Consul reads to validate workload JWTs (nomad-workloads
  # auth method). Only its unauthenticated JWKS is fetched.
  nomad_jwks_url = "${local.nomad_address}/.well-known/jwks.json"

  # Vault's only plaintext (http) listener — node-local, on the docker bridge,
  # intentionally not exposed more broadly. Used as the base for AIA/CRL/OCSP
  # URLs baked into issued certs, which want an http endpoint (fetching a CRL
  # over https would itself need TLS validation — a loop). The tradeoff: these
  # URLs are unreachable off the Vault node, so off-node AIA-chasing and
  # revocation checks don't work — acceptable while certs are served full-chain
  # against a trusted root and we don't rely on CRL/OCSP.
  vault_plaintext_base = "http://172.17.0.1:8200"
}
