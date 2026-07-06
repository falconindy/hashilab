variable "backend" {
  description = "Mount path for the Vault Consul secrets engine."
  type        = string
  default     = "consul"
}

variable "consul_address" {
  description = "Consul HTTP API address (host:port, no scheme) the engine uses to mint/revoke child tokens. Deployment-specific: required, no default."
  type        = string
}

variable "scheme" {
  description = "URI scheme the engine uses to reach Consul. https relies on the Vault servers trusting the home CA via their OS trust store."
  type        = string
  default     = "https"
}

variable "engine_token_name" {
  description = "Description of the dedicated Consul management token the engine authenticates with."
  type        = string
  default     = "vault-consul-secrets-engine"
}

variable "role_name" {
  description = "Name of the creds role. `vault read <backend>/creds/<role>` mints a break-glass management token."
  type        = string
  default     = "mgmt"
}
