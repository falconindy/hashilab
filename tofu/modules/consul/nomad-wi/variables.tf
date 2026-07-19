variable "nomad_jwks_url" {
  description = "Nomad's JWKS endpoint Consul reads to validate workload JWTs. Deployment-specific: required, no default."
  type        = string
}

variable "task_identity_roles" {
  description = <<-EOT
    Extra Consul roles granted to specific Nomad *task* workload identities (the
    token from a task's consul{} block) on top of the baseline nomad-tasks role.
    Keyed by role name; each carries a `policy_file` (a filename under this
    module's policies/ dir, whose module-owned policy the role attaches) and a
    Consul binding-rule `selector` matched against the task identity's JWT claims.
    For the few workloads that need more than catalog read: the connectaware
    Traefik ingresses (service:write on their own service, for Connect leaf certs)
    and Prometheus (agent:read, to scrape Consul telemetry). Binding rules are
    additive, so these tokens get nomad-tasks ∪ this role.
  EOT
  type = map(object({
    policy_file = string
    selector    = string
  }))
  default = {}
}
