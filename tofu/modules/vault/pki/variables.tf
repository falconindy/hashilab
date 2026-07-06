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
  description = "Mount path for the root PKI engine."
  type        = string
  default     = "pki"
}

variable "common_name" {
  description = "CN for the self-signed root CA certificate."
  type        = string
  default     = "home"
}

variable "issuer_name" {
  description = <<-EOT
    issuer_name stamped on the generated root, conventionally year-based
    (e.g. root-2026). tofu can't derive the year at plan time without forcing
    perpetual drift, so it's an explicit input — the intermediate module
    references this same name as its signing issuer_ref.
  EOT
  type        = string
  default     = "root-2026"
}

variable "max_lease_ttl_seconds" {
  description = "max-lease-ttl for the mount. 87600h = 10y."
  type        = number
  default     = 315360000 # 87600h
}

variable "root_ttl" {
  description = "TTL Vault stamps on the self-signed root cert."
  type        = string
  default     = "87600h"
}

variable "role_name" {
  description = "Name of the issuing role created on this backend."
  type        = string
  default     = "servers"
}

variable "bootstrap" {
  description = <<-EOT
    Generate the self-signed root CA. This is a one-shot cold-start action that
    produces new root key material — DO NOT enable it against a cluster whose
    root `pki` already exists, or an apply will mint a NEW root and detonate
    trust everywhere (every node trusts the current root at
    /etc/ssl/certs/home.pem). Leave false and `tofu import` the existing mount/
    role/config instead. Set true only on a truly green-field Vault.
  EOT
  type        = bool
  default     = false
}
