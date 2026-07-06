output "path" {
  description = "Mount path of the OIDC auth method."
  value       = vault_jwt_auth_backend.oidc.path
}

output "accessor" {
  description = "Auth method accessor — needed to wire external identity groups (e.g. mapping a Pocket-ID group claim to a Vault policy)."
  value       = vault_jwt_auth_backend.oidc.accessor
}

output "role_name" {
  description = "Name of the OIDC role."
  value       = vault_jwt_auth_backend_role.role.role_name
}
