variable "cluster_base" {
  description = "scheme://host:port Vault serves this engine's cluster path at (backs OCSP, and the ACME directory on ACME mounts). Must be reachable by the relevant clients. Deployment-specific: required, no default."
  type        = string
}

variable "aia_base" {
  description = <<-EOT
    scheme://host:port templated into issued certs' AIA / CRL URLs. Defaults to
    cluster_base. Conventionally a *plaintext* (http) endpoint, since fetching a
    CRL/issuer over https would itself need TLS validation (a loop). Point it at
    a cluster-reachable http listener if you have one; a node-local one means
    off-node AIA/CRL fetches won't resolve.
  EOT
  type        = string
  default     = null
}

variable "backend" {
  description = "Mount path for this internal intermediate PKI engine."
  type        = string
  default     = "pki_int_internal"
}

variable "common_name" {
  description = "CN for the intermediate CA certificate."
  type        = string
  default     = "home Vault Intermediate Authority [Internal]"
}

variable "root_backend" {
  description = "Mount path of the root PKI engine that signs this intermediate."
  type        = string
  default     = "pki"
}

variable "root_issuer_ref" {
  description = "issuer_ref on the root backend used to sign the intermediate CSR (name, UUID, or \"default\")."
  type        = string
  default     = "default"
}

variable "max_lease_ttl_seconds" {
  description = "max-lease-ttl for the mount. 43800h = 5y, shorter than the 10y root."
  type        = number
  default     = 157680000 # 43800h
}

variable "intermediate_sign_ttl" {
  description = "TTL Vault stamps on the signed intermediate cert."
  type        = string
  default     = "43800h"
}

variable "role_name" {
  description = "Name of the issuing role created on this backend."
  type        = string
  default     = "intermediate"
}

variable "role_max_ttl_seconds" {
  description = "max_ttl for client certs issued through the role. 4380h = ~6mo."
  type        = number
  default     = 15768000 # 4380h
}

variable "bootstrap" {
  description = <<-EOT
    Generate the intermediate key, have the root sign it, and import the result.
    One-shot cold-start action that produces new CA key material — DO NOT enable
    against a cluster whose pki_int_internal already exists, or an apply will
    re-sign a fresh intermediate and break the live chain. Leave false and
    `tofu import` the existing mount/role/config instead. Set true only on a
    green-field mount.
  EOT
  type        = bool
  default     = false
}
