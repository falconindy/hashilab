output "auth_method_name" {
  description = "Name of the OIDC auth method. `nomad login -method=<this>`."
  value       = nomad_acl_auth_method.pocket_id.name
}

output "binding_rule_id" {
  description = "ID of the pocket-id -> admin binding rule."
  value       = nomad_acl_binding_rule.admin.id
}
