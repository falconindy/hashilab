variable "nomad_address" {
  description = "External URL of the Nomad cluster, used to build the UI redirect URI. Deployment-specific: required, no default."
  type        = string
}

variable "auth_method_name" {
  description = "Name of the OIDC auth method. `nomad login -method=<this>`."
  type        = string
  default     = "pocket-id"
}

variable "oidc_discovery_url" {
  description = "Issuer / OIDC discovery URL (Pocket-ID). Deployment-specific: required, no default."
  type        = string
}

variable "oidc_client_id" {
  description = "OIDC client ID from the Pocket-ID \"Nomad\" client (distinct from the Vault client). Provide via TF_VAR_nomad_oidc_client_id."
  type        = string
}

variable "oidc_client_secret" {
  description = "OIDC client secret from the Pocket-ID \"Nomad\" client. Provide via TF_VAR_nomad_oidc_client_secret."
  type        = string
  sensitive   = true
}

variable "oidc_scopes" {
  description = "Scopes requested from Pocket-ID."
  type        = list(string)
  default     = ["openid", "profile"]
}

variable "oidc_enable_pkce" {
  description = "Use PKCE on the OIDC exchange."
  type        = bool
  default     = true
}

variable "claim_mappings" {
  description = "Maps OIDC claims to Nomad token metadata values. preferred_username -> user feeds token_name_format."
  type        = map(string)
  default     = { preferred_username = "user" }
}

variable "is_default" {
  description = "Make this the default auth method `nomad login` selects."
  type        = bool
  default     = true
}

variable "token_locality" {
  description = "\"global\" so the token works across regions, or \"local\"."
  type        = string
  default     = "global"
}

variable "max_token_ttl" {
  description = "Maximum TTL for tokens minted via this method."
  type        = string
  default     = "8h"
}

variable "token_name_format" {
  description = "Template for minted token names. Nomad-side interpolation, so the $${...} are escaped from tofu."
  type        = string
  default     = "$${auth_method_name}-$${value.user}"
}

variable "bind_policy_name" {
  description = "Policy every user authenticating through this method is bound to. No selector — access is gated on the Pocket-ID client."
  type        = string
  default     = "admin"
}

variable "extra_redirect_uris" {
  description = "Additional allowed redirect URIs beyond the computed UI + CLI callbacks. Must also be registered on the Pocket-ID client."
  type        = list(string)
  default     = []
}
