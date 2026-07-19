variable "owned_policy_files" {
  description = "Filenames under this module's policies/ dir whose vault_policy the module creates and attaches to the role. vault-agent uses internal-server-certs (renders TLS from pki_int_internal)."
  type        = list(string)
  default     = []
}

# token_bound_cidrs/token_ttl_seconds default to null = "adopt whatever the live
# role has" (unset, so the provider doesn't force a value). Pin them only if you
# want tofu to own the value; set them to match
# `vault read auth/approle/role/vault-agent` if an import shows drift.

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

variable "token_type" {
  description = "Token type the role mints. vault-agent uses `batch` (lightweight, re-auths on expiry)."
  type        = string
  default     = "default"
}
