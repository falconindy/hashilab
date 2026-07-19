output "daemon_token_accessors" {
  description = "Map of daemon token name -> accessor ID (safe to expose; not the secret)."
  value       = { for k, t in consul_acl_token.daemon : k => t.accessor_id }
}

output "kv_paths" {
  description = "Vault KV paths the daemon tokens are stashed under, for the Ansible roles."
  value       = { for k, s in vault_kv_secret_v2.daemon : k => "kv/${s.name}" }
}
