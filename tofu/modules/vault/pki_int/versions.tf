terraform {
  required_version = ">= 1.6"

  required_providers {
    # `vault_pki_secret_backend_config_auto_tidy` landed in provider 4.7; keep
    # the floor there (above the 4.3 needed for the ACME config resource).
    vault = {
      source  = "hashicorp/vault"
      version = ">= 4.7"
    }
  }
}
