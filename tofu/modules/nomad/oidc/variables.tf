variable "nomad_address" {
  description = "External URL of the Nomad cluster, used to build the UI redirect URI. Deployment-specific: required, no default."
  type        = string
}

variable "oidc_discovery_url" {
  description = "Issuer / OIDC discovery URL (Pocket-ID). Deployment-specific: required, no default."
  type        = string
}

variable "oidc_client_id" {
  description = "OIDC client ID from the Pocket-ID \"Nomad\" client (distinct from the Vault client). Wired from the root local.nomad_oidc_client_id."
  type        = string
}
