variable "vault_address" {
  description = "External URL of the Vault cluster, used to build the UI redirect URI. Deployment-specific: required, no default."
  type        = string
}

variable "path" {
  description = "Mount path for the OIDC auth method."
  type        = string
  default     = "oidc"
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

variable "role_name" {
  description = "Name of the OIDC role. Also set as the backend's default_role so `vault login -method=oidc` needs no -role."
  type        = string
  default     = "admin"
}

variable "user_claim" {
  description = "Token claim used as the Vault identity. email gives readable audit entries (requires the email scope)."
  type        = string
  default     = "email"
}

variable "oidc_scopes" {
  description = "Scopes requested from Pocket-ID. email is required if user_claim is email."
  type        = list(string)
  default     = ["profile", "email"]
}

variable "token_policies" {
  description = "Policies attached to tokens minted for this role."
  type        = list(string)
  default     = ["admin"]
}

variable "extra_redirect_uris" {
  description = "Additional allowed redirect URIs beyond the computed UI + CLI callbacks. Must also be registered on the Pocket-ID client."
  type        = list(string)
  default     = []
}

variable "token_ttl_seconds" {
  description = "Default token TTL. Short renewable TTLs limit a leaked token. 7200 = 2h."
  type        = number
  default     = 7200
}

variable "token_max_ttl_seconds" {
  description = "Maximum token TTL. 28800 = 8h."
  type        = number
  default     = 28800
}
