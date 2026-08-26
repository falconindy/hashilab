output "backend" {
  description = "Mount path of the AppRole auth method."
  value       = vault_auth_backend.approle.path
}

output "role_name" {
  description = "Name of the vault-agent AppRole role."
  value       = vault_approle_auth_backend_role.this.role_name
}

output "role_id" {
  description = "The role's role_id, rendered live to /etc/vault-agent.d/agent.roleid by the vault_agent Ansible role — not a static file to diff against."
  value       = vault_approle_auth_backend_role.this.role_id
}
