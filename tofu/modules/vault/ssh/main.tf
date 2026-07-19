# ── The mount ────────────────────────────────────────────────────────────────
# Equivalent to: `vault secrets enable -path=ssh-client-signer ssh`.
resource "vault_mount" "ssh" {
  path        = "ssh-client-signer"
  type        = "ssh"
  description = "SSH client-certificate CA — signs short-lived certs off an OIDC login."
}

# ── The CA signing keypair ───────────────────────────────────────────────────
# Equivalent to: `vault write <mount>/config/ca generate_signing_key=true`.
#
# One-shot cold-start ACTION that generates CA key material. Gated behind
# var.bootstrap (default false) so a normal plan/apply can NEVER re-generate the
# CA — which would invalidate the public key every host trusts as
# TrustedUserCAKeys. The private half never leaves Vault; the public half is
# distributed to hosts out of band. Enable only on a green-field mount.
resource "vault_ssh_secret_backend_ca" "this" {
  count                = var.bootstrap ? 1 : 0
  backend              = vault_mount.ssh.path
  generate_signing_key = true
}

# ── The signing role ─────────────────────────────────────────────────────────
# permit-pty is the minimum for an interactive shell; forwarding is convenience.
resource "vault_ssh_secret_backend_role" "admin" {
  backend                 = vault_mount.ssh.path
  name                    = "admin"
  key_type                = "ca"
  algorithm_signer        = "rsa-sha2-256"
  allow_user_certificates = true
  allowed_users           = "root"
  allowed_users_template  = false
  default_user            = "root"
  allowed_extensions      = "permit-pty,permit-port-forwarding,permit-agent-forwarding"
  default_extensions = {
    "permit-pty" = ""
  }
  ttl     = "1800" # 30m
  max_ttl = "7200" # 2h

  # The role can only be created once its CA exists. On an existing cluster the
  # CA is already there (bootstrap=false → this depends_on is a no-op).
  depends_on = [vault_ssh_secret_backend_ca.this]
}
