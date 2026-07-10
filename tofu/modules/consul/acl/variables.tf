variable "kv_mount" {
  description = "Vault KV v2 mount the daemon tokens are stashed under (kv/consul/tokens/<name>)."
  type        = string
  default     = "kv"
}

variable "anonymous_policy_file" {
  description = "Filename under this module's policies/ dir whose policy attaches to the built-in anonymous token."
  type        = string
  default     = "anonymous.hcl"
}

variable "daemon_token_policy_files" {
  description = <<-EOT
    Filenames under this module's policies/ dir to mint a non-expiring daemon
    token for. Each token (and its KV path kv/consul/tokens/<name>) is named after
    the file minus .hcl and carries the like-named policy. The anonymous policy is
    NOT here — it's an attachment (var.anonymous_policy_file), not a token.
  EOT
  type        = set(string)
  default = [
    "consul-agent.hcl",
    "consul-config-services.hcl",
    "nomad-agent.hcl",
    "vault-registration.hcl",
  ]
}
