variable "vault_address" {
  description = "External URL of the Vault cluster, used to build the UI redirect URI. Deployment-specific: required, no default."
  type        = string
}

variable "oidc_discovery_url" {
  description = "Issuer / OIDC discovery URL (Pocket-ID). Deployment-specific: required, no default."
  type        = string
}

variable "oidc_client_id" {
  description = "OIDC client ID from the Pocket-ID \"Vault\" client. Wired from the root var.vault_oidc_client_id (TF_VAR_vault_oidc_client_id)."
  type        = string
}

variable "oidc_client_secret" {
  description = "OIDC client secret from the Pocket-ID \"Vault\" client. Wired from the root var.vault_oidc_client_secret."
  type        = string
  sensitive   = true
}
