# Consul Connect CA provider — least-privilege per HashiCorp's Vault CA provider
# guide, scoped to our root (pki) and the Connect intermediate (pki_int_connect).
# Consul manages the intermediate and rotates all mesh leaf certs; the root stays
# tofu-owned and is only reachable for sign-intermediate.

# Enumerate mounts + read the root mount config — existence checks Consul runs at
# CA init.
path "sys/mounts" {
  capabilities = ["read"]
}

path "pki" {
  capabilities = ["read"]
}

# Manage the intermediate mount. pki_int_connect is pre-created by tofu, but grant
# mount + tune so Consul's provider lifecycle can (re)mount/tune it rather than
# wedging CA init on a missing capability.
path "sys/mounts/pki_int_connect" {
  capabilities = ["create", "read", "update"]
}

path "sys/mounts/pki_int_connect/tune" {
  capabilities = ["update"]
}

# Full control of the intermediate engine: generate the intermediate, import the
# signed cert, issue and rotate Connect leaf certs.
path "pki_int_connect/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# The one root path Consul may touch: sign its intermediate CSR.
path "pki/root/sign-intermediate" {
  capabilities = ["update"]
}

# Auto-renew the provider's own auth_method-issued token.
path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}
