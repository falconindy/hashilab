variable "backend" {
  description = "Mount path for the AppRole auth method."
  type        = string
  default     = "approle"
}

variable "role_name" {
  description = "Name of the AppRole role vault-agent authenticates as. VERIFY against `vault list auth/<backend>/role`."
  type        = string
  default     = "vault-agent"
}

variable "token_policies" {
  description = "External policy names (from policies.tf, by reference) attached to tokens the role mints. For policies this module owns, use owned_policy_files instead."
  type        = list(string)
  default     = []
}

variable "owned_policy_files" {
  description = "Filenames under this module's policies/ dir whose vault_policy the module creates and attaches to the role. vault-agent uses internal-server-certs (renders TLS from pki_int_internal)."
  type        = list(string)
  default     = []
}

variable "bind_secret_id" {
  description = "Whether login requires a secret_id. False here: vault-agent presents role_id alone (no secret_id_file_path in agent.hcl)."
  type        = bool
  default     = false
}

# The following default to null = "adopt whatever the live role has" (unset, so
# the provider doesn't force a value). Pin them only if you want tofu to own the
# value. Set them to match `vault read auth/<backend>/role/<role_name>` if an
# import shows drift.

variable "secret_id_bound_cidrs" {
  description = "CIDRs a secret_id may be used from. Usually irrelevant with bind_secret_id=false."
  type        = list(string)
  default     = null
}

variable "token_bound_cidrs" {
  description = "CIDRs the minted token may be used from."
  type        = list(string)
  default     = null
}

variable "token_ttl_seconds" {
  description = "Default TTL for minted tokens. null = adopt the role's existing value."
  type        = number
  default     = null
}

variable "token_max_ttl_seconds" {
  description = "Maximum TTL for minted tokens. null = adopt the role's existing value."
  type        = number
  default     = null
}

variable "token_type" {
  description = "Token type the role mints. vault-agent uses `batch` (lightweight, re-auths on expiry)."
  type        = string
  default     = "default"
}
