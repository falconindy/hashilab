output "backend" {
  description = "Mount path of the Vault Consul secrets engine."
  value       = vault_consul_secret_backend.consul.path
}

output "role_name" {
  description = "Creds role name. Mint a break-glass token with `vault read <backend>/creds/<role>`."
  value       = vault_consul_secret_backend_role.mgmt.name
}

output "engine_token_accessor" {
  description = "Accessor of the dedicated management token the engine uses (safe to expose; not the secret)."
  value       = consul_acl_token.engine.accessor_id
}
