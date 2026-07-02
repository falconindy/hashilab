# admin.hcl — near-root policy for the solo sysadmin.
#
# This is effectively root-equivalent for day-to-day work, but unlike the root
# token it is a named, revocable, TTL'd identity that shows up in the audit log.
# Attach it to a human auth method (OIDC via pocket-id, or userpass as a
# cold-start backstop), log in, verify, then revoke the root token. Recover root
# via `vault operator generate-root` from the unseal key shares if ever needed.
#
# Apply with:
#   vault policy write admin admin.hcl

# Manage auth methods broadly.
path "auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Create, update, and delete auth method configs.
path "sys/auth/*" {
  capabilities = ["create", "update", "delete", "sudo"]
}

# List auth methods.
path "sys/auth" {
  capabilities = ["read"]
}

# Manage ACL policies.
path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Enable and manage secret engines.
path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# List secret engines.
path "sys/mounts" {
  capabilities = ["read"]
}

# Read and manage all secret engine data (KV, PKI, etc.).
#
# Tighten this if desired: drop the bare "*" and instead enumerate the mounts in
# use (e.g. "secret/*", "kv/*", "pki/*", "pki_int/*", "pki_int_internal/*") so a
# typo can't reach a path you didn't intend.
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Cluster health.
path "sys/health" {
  capabilities = ["read", "sudo"]
}

# Manage leases.
path "sys/leases/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Read and manage audit devices.
path "sys/audit" {
  capabilities = ["read", "sudo"]
}

path "sys/audit/*" {
  capabilities = ["create", "update", "delete", "sudo"]
}
