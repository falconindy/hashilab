output "auth_method_name" {
  description = "Name of the Consul JWT auth method for Nomad workload identity."
  value       = consul_acl_auth_method.nomad_workloads.name
}

output "nomad_tasks_role_name" {
  description = "Name of the role serviceless Nomad tasks bind to."
  value       = consul_acl_role.nomad_tasks.name
}
