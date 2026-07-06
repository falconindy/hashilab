terraform {
  required_version = ">= 1.6"

  required_providers {
    # No ACME here, so no dependency on the 4.3 acme-config resource.
    vault = {
      source  = "hashicorp/vault"
      version = ">= 4.0"
    }
  }
}
