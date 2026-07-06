variable "kv_mount" {
  description = "Vault KV v2 mount the daemon tokens are stashed under (kv/consul/tokens/<name>)."
  type        = string
  default     = "kv"
}

variable "anonymous_policy_name" {
  description = "Name of the Consul policy to attach to the built-in anonymous token. Pass the policies.tf resource attribute so this orders after the policy is created."
  type        = string
}

variable "daemon_policy_names" {
  description = <<-EOT
    Map of daemon token name -> the Consul policy name it carries. Drives both the
    minted tokens and their KV paths (kv/consul/tokens/<key>). Pass policies.tf
    resource attributes as the values so token creation orders after the policies
    exist. Expected keys: consul-agent, nomad-agent, vault-registration.
  EOT
  type        = map(string)
}
