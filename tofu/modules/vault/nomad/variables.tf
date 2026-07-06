variable "backend" {
  description = "Mount path for the Vault Nomad secrets engine."
  type        = string
  default     = "nomad"
}

variable "nomad_address" {
  description = "Nomad API address the engine uses to mint/revoke child tokens. Deployment-specific: required, no default."
  type        = string
}

variable "engine_token_name" {
  description = "Name of the dedicated Nomad management token the engine authenticates with."
  type        = string
  default     = "vault-nomad-secrets-engine"
}

variable "role_name" {
  description = "Name of the creds role. `vault read <backend>/creds/<role>` mints a break-glass management token."
  type        = string
  default     = "mgmt"
}

variable "creds_ttl_seconds" {
  description = <<-EOT
    Default lease TTL for minted Nomad tokens — the `ttl` on nomad/config/lease
    (NOT the mount tune). When the lease ends, Vault revokes the Nomad token.
    Kept short because these are break-glass management tokens, renewable up to
    creds_max_ttl. 3600 = 1h. (config/lease is also the object the vault provider
    keys the backend's existence on, so managing it here means it always exists.)
  EOT
  type        = number
  default     = 3600 # 1h
}

variable "creds_max_ttl_seconds" {
  description = "Maximum lease TTL for minted Nomad tokens — the `max_ttl` on nomad/config/lease, the renewal ceiling. 28800 = 8h."
  type        = number
  default     = 28800 # 8h
}
