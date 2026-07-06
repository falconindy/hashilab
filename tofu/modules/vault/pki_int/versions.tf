terraform {
  required_version = ">= 1.6"

  required_providers {
    # `vault_pki_secret_backend_config_acme` landed in provider 4.3; keep the
    # floor there so the ACME config resource is available.
    vault = {
      source  = "hashicorp/vault"
      version = ">= 4.3"
    }
  }
}
