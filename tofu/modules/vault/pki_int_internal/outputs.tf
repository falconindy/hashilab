output "backend" {
  description = "Mount path of the internal intermediate PKI engine."
  value       = vault_mount.pki_int_internal.path
}

output "role_name" {
  description = "Name of the issuing role (destination for issue/sign requests)."
  value       = vault_pki_secret_backend_role.intermediate.name
}

output "issuing_ca" {
  description = "PEM of the signed intermediate CA certificate (null unless bootstrap=true)."
  value       = var.bootstrap ? vault_pki_secret_backend_root_sign_intermediate.signed[0].certificate : null
}

output "ca_chain" {
  description = "Full CA chain (intermediate + root) as returned by the root signer (null unless bootstrap=true)."
  value       = var.bootstrap ? vault_pki_secret_backend_root_sign_intermediate.signed[0].ca_chain : null
}
