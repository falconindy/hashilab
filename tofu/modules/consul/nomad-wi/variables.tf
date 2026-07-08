variable "auth_method_name" {
  description = "Name of the Consul JWT auth method Nomad workloads log in through."
  type        = string
  default     = "nomad-workloads"
}

variable "nomad_jwks_url" {
  description = "Nomad's JWKS endpoint Consul reads to validate workload JWTs. Deployment-specific: required, no default."
  type        = string
}

variable "home_ca_file" {
  description = "Path to the home CA PEM Consul uses to validate Nomad's HTTPS JWKS endpoint. Read at plan time on the machine running tofu."
  type        = string
  default     = "/etc/ssl/certs/home.pem"
}

variable "nomad_tasks_role_name" {
  description = "Name of the Consul role serviceless Nomad tasks bind to."
  type        = string
  default     = "nomad-tasks"
}

variable "nomad_tasks_policy_name" {
  description = "Name of the Consul policy the nomad-tasks role carries. Pass the policies.tf resource attribute so the role orders after the policy is created."
  type        = string
}

variable "task_identity_roles" {
  description = <<-EOT
    Extra Consul roles granted to specific Nomad *task* workload identities (the
    token from a task's consul{} block) on top of the baseline nomad-tasks role.
    Keyed by role name; each carries a `policy_name` (pass the policies.tf
    resource attribute so the role orders after its policy) and a Consul binding-
    rule `selector` matched against the task identity's JWT claims. For the few
    workloads that need more than catalog read: the connectaware Traefik ingresses
    (service:write on their own service, for Connect leaf certs) and Prometheus
    (agent:read, to scrape Consul telemetry). Binding rules are additive, so these
    tokens get nomad-tasks ∪ this role.
  EOT
  type = map(object({
    policy_name = string
    selector    = string
  }))
  default = {}
}
