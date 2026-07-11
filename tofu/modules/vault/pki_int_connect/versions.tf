terraform {
  required_version = ">= 1.6"

  required_providers {
    # Vault-only: the Connect-side ca_config change is applied out of band with
    # `consul connect ca set-config`, not by a tofu resource.
    vault = {
      source  = "hashicorp/vault"
      version = ">= 4.0"
    }
  }
}
