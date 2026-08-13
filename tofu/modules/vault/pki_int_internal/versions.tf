terraform {
  required_version = ">= 1.6"

  required_providers {
    # `vault_pki_secret_backend_config_auto_tidy` landed in provider 4.7; no
    # ACME here, so that's the only floor requirement.
    vault = {
      source  = "hashicorp/vault"
      version = ">= 4.7"
    }
  }
}
