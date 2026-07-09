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

variable "templated_policy_name" {
  description = "Name of the accessor-templated per-workload policy this module renders and owns (from templates/nomad-workloads.hcl.tftpl). Roles opt in via roles[*].include_templated_policy."
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
    JWT roles keyed by role name. Each carries token_policies (pass policies.tf
    resource attributes so the role orders after those policies exist) and an
    optional include_templated_policy: set it true to prepend the module's
    accessor-templated per-workload policy (the default role, nomad-workloads,
    wants this; a role like raft-snapshotter does not). Nomad's bare vault{}
    blocks resolve to default_role; other jobs name their role explicitly.

    Optional bound_claims / bound_claims_type gate WHICH workloads may assume the
    role: without them, ANY job in the cluster can name the role in its vault{}
    block (user_claim only identifies the entity, it doesn't restrict login). Set
    e.g. { nomad_job_id = "cluster-config-snapshotter/periodic-*" } with type
    "glob" to pin a privileged role to one job — note periodic/batch children
    carry the dispatched id (<parent>/periodic-<ts>), not the bare parent name.
    The default role stays unbound on purpose (it's the catch-all, and its
    templated policy self-scopes each token to kv/<namespace>/<job_id>/*).
  EOT
  type = map(object({
    token_policies           = list(string)
    include_templated_policy = optional(bool, false)
    bound_claims             = optional(map(string))
    bound_claims_type        = optional(string)
  }))
}

variable "token_period_seconds" {
  description = "Period for the (periodic) workload tokens. Nomad renews on this interval for the alloc's life; token_ttl/token_max_ttl stay 0 (no hard cap). 1800 = 30m, matching live."
  type        = number
  default     = 1800
}
