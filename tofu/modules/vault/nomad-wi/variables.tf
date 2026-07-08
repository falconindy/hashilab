variable "auth_method_path" {
  description = "Mount path for the JWT auth method Nomad workloads log in through. Matches the live mount (`vault auth list`)."
  type        = string
  default     = "jwt-nomad"
}

variable "default_role" {
  description = "Role Nomad's bare vault{} blocks (no `role`) resolve to, set as the mount's default_role. Must be a key in var.roles."
  type        = string
  default     = "nomad-workloads"
}

variable "nomad_jwks_url" {
  description = <<-EOT
    Nomad's JWKS endpoint Vault reads to validate workload JWTs. This is the
    NODE-LOCAL agent (https://localhost:4646/...), not the cluster DNS name the
    Consul method uses — Vault runs co-located with a Nomad agent on every server.
    No CA is embedded (jwks_ca_pem stays empty); validation uses the node's system
    trust store.
  EOT
  type        = string
  default     = "https://localhost:4646/.well-known/jwks.json"
}

variable "bound_audience" {
  description = "Audience the login JWT must carry. MUST equal the `aud` in Nomad's vault{} default_identity block (os/etc/nomad.d/base.hcl.j2 → \"vault.io\")."
  type        = string
  default     = "vault.io"
}

variable "roles" {
  description = <<-EOT
    JWT roles keyed by role name; each carries a list of token_policies. Nomad's
    default workloads use `nomad-workloads` (the templated per-job policy +
    prometheus-metrics); jobs that name a different role select it explicitly
    (e.g. `raft-snapshotter`). Pass the policies.tf resource attributes so each
    role orders after its policies are created.
  EOT
  type = map(object({
    token_policies = list(string)
  }))
}

variable "token_period_seconds" {
  description = "Period for the (periodic) workload tokens. Nomad renews on this interval for the alloc's life; token_ttl/token_max_ttl stay 0 (no hard cap). 1800 = 30m, matching live."
  type        = number
  default     = 1800
}
