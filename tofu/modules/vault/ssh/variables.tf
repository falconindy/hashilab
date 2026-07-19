variable "bootstrap" {
  description = <<-EOT
    Generate the CA signing keypair (config/ca generate_signing_key=true). This
    is a one-shot cold-start action that produces new key material — DO NOT
    enable it against a cluster whose ssh-client-signer CA already exists, or an
    apply mints a NEW CA and every host's TrustedUserCAKeys
    (/etc/ssh/trusted-user-ca-keys.pem, distributed out of band from
    <backend>/public_key) stops matching, locking you out. Leave false for an
    existing engine; set true only on a green-field mount.
  EOT
  type        = bool
  default     = false
}
