# ssh.hcl — sign SSH client certificates off the Vault SSH CA.
#
# Stood up by bin/vault-build-ssh on the `ssh-client-signer` mount. The `admin`
# policy already covers this (it has path "*"), so this exists to grant SSH
# access to a less-privileged identity without handing out admin.
#
# Apply with:
#   vault policy write ssh ssh.hcl

# Sign a public key against the admin signing role.
path "ssh-client-signer/sign/admin" {
  capabilities = ["create", "update"]
}
