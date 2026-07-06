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
  description = "Mount path for this intermediate PKI engine."
  type        = string
  default     = "pki_int"
}

variable "common_name" {
  description = "CN for the intermediate CA certificate."
  type        = string
  default     = "home Vault Intermediate Authority"
}

variable "root_backend" {
  description = "Mount path of the root PKI engine that signs this intermediate (managed out of band / by a separate module)."
  type        = string
  default     = "pki"
}

variable "root_issuer_ref" {
  description = <<-EOT
    issuer_ref on the root backend used to sign the intermediate CSR. The
    build-pki script names the root issuer `root-YYYY` (e.g. root-2026); pass
    that name, or an issuer UUID, or "default" to use the root's default issuer.
  EOT
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
  description = "max_ttl for leaf certs issued through the role. 768h = 32d."
  type        = number
  default     = 2764800 # 768h
}

variable "acme_enabled" {
  description = "Enable the ACME directory on this backend (Traefik uses it for *.service.home)."
  type        = bool
  default     = true
}

variable "bootstrap" {
  description = <<-EOT
    Generate the intermediate key, have the root sign it, and import the result.
    This is a one-shot cold-start action that produces new CA key material — DO
    NOT enable it against a cluster whose pki_int already exists, or an apply
    will re-sign a fresh intermediate and break the live chain. Leave false and
    `tofu import` the existing mount/role/config instead. Set true only on a
    green-field mount.
  EOT
  type        = bool
  default     = false
}
