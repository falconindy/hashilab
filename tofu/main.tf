variable "root_issuer_name" {
  description = "issuer_name of the root CA, conventionally root-YYYY; feeds both the root and the intermediate's signing issuer_ref."
  type        = string
  default     = "root-2026"
}

variable "bootstrap" {
  description = <<-EOT
    Green-field cold start: generate the root, then generate + sign + import the
    intermediate. Leave false for an existing cluster (import the mounts/roles/
    config instead — see README). Applies to the PKI/SSH modules (the OIDC module
    has no key material, so it's always managed).
  EOT
  type        = bool
  default     = false
}

variable "vault_oidc_client_id" {
  description = "Pocket-ID \"Vault\" client ID. Supply in secrets.auto.tfvars (or TF_VAR_vault_oidc_client_id)."
  type        = string
}

variable "vault_oidc_client_secret" {
  description = "Pocket-ID \"Vault\" client secret. Supply in secrets.auto.tfvars (gitignored)."
  type        = string
  sensitive   = true
}

variable "nomad_oidc_client_id" {
  description = "Pocket-ID \"Nomad\" client ID (a DIFFERENT client from Vault's). Supply in secrets.auto.tfvars."
  type        = string
}

variable "nomad_oidc_client_secret" {
  description = "Pocket-ID \"Nomad\" client secret. Supply in secrets.auto.tfvars (gitignored)."
  type        = string
  sensitive   = true
}

module "vault_pki" {
  source = "./modules/vault/pki"

  # Root has no ACME; its cluster path only backs OCSP. Keep it on the plaintext,
  # node-local endpoint (AIA/CRL/OCSP over http, loop-free).
  cluster_base = local.vault_plaintext_base
  backend      = "pki"
  common_name  = "home"
  issuer_name  = var.root_issuer_name
  bootstrap    = var.bootstrap
}

module "vault_pki_int" {
  source = "./modules/vault/pki_int"

  # ACME mount: the cluster path is the ACME directory Traefik talks to, so it
  # must be the https/DNS endpoint. aia_base defaults to cluster_base, so the
  # *.service.home leaf certs carry https/DNS AIA (current behavior). Set
  # aia_base = local.vault_plaintext_base if you'd rather their AIA/CRL be
  # loop-free http — at the cost of off-node CRL fetches not resolving.
  cluster_base = local.vault_address
  backend      = "pki_int"
  common_name  = "home Vault Intermediate Authority"
  root_backend = module.vault_pki.backend
  # Chain the intermediate's signing issuer to the root the pki module owns.
  root_issuer_ref = module.vault_pki.issuer_name
  acme_enabled    = true
  bootstrap       = var.bootstrap
}

module "vault_pki_int_internal" {
  source = "./modules/vault/pki_int_internal"

  # No ACME; cluster path only backs OCSP. Plaintext node-local, like the root.
  cluster_base    = local.vault_plaintext_base
  backend         = "pki_int_internal"
  common_name     = "home Vault Intermediate Authority [Internal]"
  root_backend    = module.vault_pki.backend
  root_issuer_ref = module.vault_pki.issuer_name
  bootstrap       = var.bootstrap
}

module "vault_ssh" {
  source = "./modules/vault/ssh"

  backend       = "ssh-client-signer"
  role_name     = "admin"
  allowed_users = "root"
  default_user  = "root"
  bootstrap     = var.bootstrap
}

module "vault_oidc" {
  source = "./modules/vault/oidc"

  vault_address      = local.vault_address
  path               = "oidc"
  oidc_discovery_url = local.oidc_discovery_url
  oidc_client_id     = var.vault_oidc_client_id
  oidc_client_secret = var.vault_oidc_client_secret
  role_name          = "admin"
  token_policies     = ["admin"]
}

module "vault_nomad" {
  source = "./modules/vault/nomad"

  backend           = "nomad"
  nomad_address     = local.nomad_address
  engine_token_name = "vault-nomad-secrets-engine"
  role_name         = "mgmt"
}

module "nomad_oidc" {
  source = "./modules/nomad/oidc"

  nomad_address      = local.nomad_address
  auth_method_name   = "pocket-id"
  oidc_discovery_url = local.oidc_discovery_url
  oidc_client_id     = var.nomad_oidc_client_id
  oidc_client_secret = var.nomad_oidc_client_secret
  bind_policy_name   = "admin"
}

output "vault_pki_backend" {
  value = module.vault_pki.backend
}

output "vault_pki_role" {
  value = module.vault_pki.role_name
}

output "vault_pki_int_backend" {
  value = module.vault_pki_int.backend
}

output "vault_pki_int_role" {
  value = module.vault_pki_int.role_name
}

output "vault_pki_int_internal_backend" {
  value = module.vault_pki_int_internal.backend
}

output "vault_pki_int_internal_role" {
  value = module.vault_pki_int_internal.role_name
}

output "vault_ssh_backend" {
  value = module.vault_ssh.backend
}

output "vault_ssh_role" {
  value = module.vault_ssh.role_name
}

output "vault_oidc_path" {
  value = module.vault_oidc.path
}

output "vault_oidc_accessor" {
  value = module.vault_oidc.accessor
}

output "vault_nomad_backend" {
  value = module.vault_nomad.backend
}

output "vault_nomad_role" {
  value = module.vault_nomad.role_name
}

output "nomad_oidc_auth_method" {
  value = module.nomad_oidc.auth_method_name
}
