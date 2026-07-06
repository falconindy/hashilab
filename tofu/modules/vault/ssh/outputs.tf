output "backend" {
  description = "Mount path of the SSH CA engine."
  value       = vault_mount.ssh.path
}

output "role_name" {
  description = "Name of the signing role."
  value       = vault_ssh_secret_backend_role.admin.name
}

output "public_key" {
  description = <<-EOT
    The CA public key hosts trust as TrustedUserCAKeys (null unless
    bootstrap=true). Also always readable unauthenticated at
    <vault_addr>/v1/<backend>/public_key — distributing it to hosts is done out
    of band, not by tofu.
  EOT
  value       = var.bootstrap ? vault_ssh_secret_backend_ca.this[0].public_key : null
}
