output "auth_method_path" {
  description = "Mount path of the JWT auth method for Nomad workload identity into Vault."
  value       = vault_jwt_auth_backend.nomad_workloads.path
}

output "auth_method_accessor" {
  description = "Accessor of the jwt-nomad mount. The nomad-workloads policy embeds this string; exposed so a drift check is easy (it's not a secret)."
  value       = vault_jwt_auth_backend.nomad_workloads.accessor
}

output "role_names" {
  description = "Names of the JWT roles managed here."
  value       = keys(vault_jwt_auth_backend_role.this)
}
