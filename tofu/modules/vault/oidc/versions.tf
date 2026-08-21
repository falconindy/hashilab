terraform {
  # Ephemeral resources (the `ephemeral` block in main.tf) need >= 1.10.
  required_version = ">= 1.10"

  required_providers {
    vault = {
      source = "hashicorp/vault"
      # oidc_client_secret_wo / oidc_client_secret_wo_version on
      # vault_jwt_auth_backend landed in 5.7.0.
      version = ">= 5.7"
    }
  }
}
