variable "backend" {
  description = "Mount path for the SSH client-signing CA engine."
  type        = string
  default     = "ssh-client-signer"
}

variable "role_name" {
  description = "Name of the signing role. Hosts trust certs signed via <backend>/sign/<role>."
  type        = string
  default     = "admin"
}

variable "allowed_users" {
  description = "Comma-separated Unix principals a signed cert may log in as. Keep tight — this gates which accounts an OIDC-issued cert can reach."
  type        = string
  default     = "root"
}

variable "default_user" {
  description = "Default principal when the signer doesn't request one."
  type        = string
  default     = "root"
}

variable "ttl_seconds" {
  description = "Default cert TTL. Short so a leaked cert is near-useless. 1800 = 30m."
  type        = string
  default     = "1800"
}

variable "max_ttl_seconds" {
  description = "Maximum cert TTL. 7200 = 2h."
  type        = string
  default     = "7200"
}

variable "bootstrap" {
  description = <<-EOT
    Generate the CA signing keypair (config/ca generate_signing_key=true). This
    is a one-shot cold-start action that produces new key material — DO NOT
    enable it against a cluster whose ssh-client-signer CA already exists, or an
    apply mints a NEW CA and every host's TrustedUserCAKeys
    (/etc/ssh/trusted-user-ca-keys.pem, distributed by the `base` ansible role
    from <backend>/public_key) stops matching, locking you out. Leave false for
    an existing engine; set true only on a green-field mount.
  EOT
  type        = bool
  default     = false
}

variable "manage_policy" {
  description = <<-EOT
    Whether this module writes the `ssh` Vault policy. Default false: the ansible
    `vault_policies` role is the source of truth for vault/policies/*.hcl (it
    write-from-repo + prunes), so letting tofu also own it would create two
    writers of the same policy. Flip true only if you're migrating policy
    ownership to tofu.
  EOT
  type        = bool
  default     = false
}

variable "policy_name" {
  description = "Name of the Vault policy to write when manage_policy = true."
  type        = string
  default     = "ssh"
}

variable "policy_document" {
  description = "HCL body of the Vault policy, used only when manage_policy = true. Feed it file(\"vault/policies/ssh.hcl\") from the root module."
  type        = string
  default     = ""
}
