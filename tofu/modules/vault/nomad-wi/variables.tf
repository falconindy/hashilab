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

    owned_policies lists filenames under this module's policies/ dir (e.g.
    "raft-snapshots.hcl") whose vault_policy the module creates and attaches to
    this role. Use it for policies that are an implementation detail of a role
    defined here (nothing outside the module references them); external policy
    names still come in via token_policies by reference from policies.tf.
  EOT
  type = map(object({
    token_policies           = list(string)
    include_templated_policy = optional(bool, false)
    owned_policies           = optional(list(string), [])
    bound_claims             = optional(map(string))
    bound_claims_type        = optional(string)
  }))
}
