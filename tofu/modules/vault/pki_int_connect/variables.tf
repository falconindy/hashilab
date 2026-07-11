variable "backend" {
  description = "Mount path for the Connect intermediate PKI engine."
  type        = string
  default     = "pki_int_connect"
}

variable "max_lease_ttl_seconds" {
  description = "max-lease-ttl for the mount. Must exceed Consul's IntermediateCertTTL (default 8760h). 43800h = 5y, shorter than the 10y root."
  type        = number
  default     = 157680000 # 43800h
}

variable "policy_name" {
  description = "Name of the Vault policy granting the Connect CA provider its access."
  type        = string
  default     = "consul-connect-ca"
}

variable "approle_backend" {
  description = "Mount path of the existing approle auth backend the connect-ca role is created on (module.vault_approle enables it)."
  type        = string
  default     = "approle"
}

variable "approle_role_name" {
  description = "Name of the keyless AppRole role the Consul servers log in with to drive the CA provider."
  type        = string
  default     = "consul-connect-ca"
}

variable "server_cidrs" {
  description = "CIDRs the connect-ca role_id may log in from — the Consul servers. bind_secret_id is false, so this CIDR bound is the login gate."
  type        = list(string)
  default     = ["10.0.100.0/24"]
}

variable "token_ttl_seconds" {
  description = "TTL of the token the CA provider gets on login. The provider auto-renews it (token_type=service)."
  type        = number
  default     = 1200 # 20m
}

variable "kv_mount" {
  description = "Vault KV v2 mount role_id is stashed under (kv/consul/connect-ca)."
  type        = string
  default     = "kv"
}
