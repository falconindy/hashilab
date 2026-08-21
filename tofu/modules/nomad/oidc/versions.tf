terraform {
  required_version = ">= 1.6"

  required_providers {
    # oidc_enable_pkce on the auth-method config needs a recent 2.x.
    nomad = {
      source  = "hashicorp/nomad"
      version = ">= 2.1"
    }
    # Reads the OIDC client secret from Vault KV (see main.tf).
    vault = {
      source  = "hashicorp/vault"
      version = ">= 4.0"
    }
  }
}
