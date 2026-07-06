terraform {
  required_version = ">= 1.6"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = ">= 4.3"
    }
    # Used only by modules/vault/nomad, to own the dedicated Nomad management
    # token the secrets engine is configured with.
    nomad = {
      source  = "hashicorp/nomad"
      version = ">= 2.0"
    }
  }

  # Where the state lives is up to you. Local state is fine for a POC, BUT once
  # modules/vault/nomad is in play the state file contains a Nomad *management*
  # token (nomad_acl_token.engine.secret_id) — treat state as a secret. Use a
  # secure backend and/or OpenTofu state encryption:
  #
  #   encryption {
  #     key_provider "pbkdf2" "k" { passphrase = "..." }   # or a KMS/Vault provider
  #     method "aes_gcm" "m" { keys = key_provider.pbkdf2.k }
  #     state  { method = method.aes_gcm.m }
  #     plan   { method = method.aes_gcm.m }
  #   }
  #
  # backend "consul" {
  #   address = "consul.service.home:8501"
  #   scheme  = "https"
  #   path    = "tofu/hashilab"
  # }
}
