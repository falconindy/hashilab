output "backend" {
  description = "Mount path of the Connect intermediate PKI engine (Consul's intermediate_pki_path)."
  value       = vault_mount.pki_int_connect.path
}

output "policy_name" {
  description = "Name of the Vault policy the CA provider role carries."
  value       = vault_policy.connect_ca.name
}

output "approle_role_name" {
  description = "Name of the keyless AppRole role the Consul servers authenticate with."
  value       = vault_approle_auth_backend_role.connect_ca.role_name
}

output "role_id" {
  description = "role_id for Consul servers' connect.ca_config auth_method. Also stashed in Vault KV (kv/consul/connect-ca) for the consul Ansible role."
  value       = vault_approle_auth_backend_role.connect_ca.role_id
}

output "kv_path" {
  description = "Vault KV path role_id is stashed under, for the consul Ansible role."
  value       = "kv/${vault_kv_secret_v2.role_id.name}"
}
