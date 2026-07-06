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
