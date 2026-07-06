output "backend" {
  description = "Mount path of the Vault Nomad secrets engine."
  value       = vault_nomad_secret_backend.nomad.backend
}

output "role_name" {
  description = "Creds role name. Mint a break-glass token with `vault read <backend>/creds/<role>`."
  value       = vault_nomad_secret_role.mgmt.role
}

output "engine_token_accessor" {
  description = "Accessor of the dedicated management token the engine uses (safe to expose; not the secret)."
  value       = nomad_acl_token.engine.accessor_id
}
