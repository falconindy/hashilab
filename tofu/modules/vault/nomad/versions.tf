terraform {
  required_version = ">= 1.7"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = ">= 5.7"
    }
    nomad = {
      source  = "hashicorp/nomad"
      version = ">= 2.4"
    }
  }
}
