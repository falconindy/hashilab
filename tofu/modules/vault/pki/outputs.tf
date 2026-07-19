output "backend" {
  description = "Mount path of the root PKI engine."
  value       = vault_mount.pki.path
}

output "issuer_name" {
  description = "issuer_name of the root — feed this to the pki_int module's root_issuer_ref."
  value       = local.issuer_name
}

output "role_name" {
  description = "Name of the issuing role."
  value       = vault_pki_secret_backend_role.servers.name
}

output "certificate" {
  description = "PEM of the self-signed root CA certificate (null unless bootstrap=true)."
  value       = var.bootstrap ? vault_pki_secret_backend_root_cert.root[0].certificate : null
}
