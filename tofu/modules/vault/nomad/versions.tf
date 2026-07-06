terraform {
  required_version = ">= 1.6"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = ">= 4.0"
    }
    nomad = {
      source  = "hashicorp/nomad"
      version = ">= 2.0"
    }
  }
}
