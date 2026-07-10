# ── The JWT auth method ──────────────────────────────────────────────────────
# The Vault-side twin of modules/consul/nomad-wi. Nomad allocations that carry a
# vault{} block mint a workload-identity JWT (aud=vault.io, see base.hcl.j2's
# default_identity) and log in here to get a short-lived, per-job Vault token —
# instead of Nomad holding one shared Vault token and handing derived tokens out.
# Replaces the hand-run `vault auth enable -path=jwt-nomad jwt` +
# `vault write auth/jwt-nomad/config ...`.
#
# ── jwks_url is Vault's *node-local* Nomad agent (localhost:4646), NOT the
# cluster DNS name the Consul method uses. Vault runs on nomad0-2, which are also
# Nomad clients, so each Vault reads its co-located agent's JWKS. Consequently
# jwks_ca_pem is intentionally EMPTY: validation rides the node's system trust
# store (the home CA is in /etc/ssl/certs on every node), not an embedded PEM.
# This is the one real divergence from the Consul method, which embeds JWKSCACert.
#
# ── Ordering: this must exist BEFORE Nomad's vault{} default_identity is live and
# BEFORE any job with a vault{} block deploys — an allocation begins its JWT login
# the moment it starts, and a missing method fails the alloc. Same "auth method
# first, workloads second" rule as the Consul side.
resource "vault_jwt_auth_backend" "nomad_workloads" {
  path = var.auth_method_path
  type = "jwt"
  # description left unset to match the live mount (empty) — a no-diff import.

  jwks_url     = var.nomad_jwks_url
  default_role = var.default_role

  # Nomad signs workload-identity JWTs with RS256, so accept only that.
  jwt_supported_algs = ["RS256"]
}

# ── The templated per-workload policy ────────────────────────────────────────
# Scopes every default workload to its own KV subtree via Vault ACL templating.
# The policy body has to embed THIS mount's accessor (auth_jwt_…) — the only way
# to say "the claims on a token minted through jwt-nomad" — so it can't live as a
# static policy file with the accessor hand-copied (that silently
# breaks the moment the mount is recreated and the accessor changes). Rendered
# here instead, with the accessor read straight off the resource, so it always
# tracks the live mount and survives a bootstrap/DR rebuild. chomp() matches how
# policies.tf stores its files (Vault strips trailing whitespace).
resource "vault_policy" "nomad_workloads" {
  name = var.templated_policy_name
  policy = chomp(templatefile("${path.module}/templates/nomad-workloads.hcl.tftpl", {
    accessor = vault_jwt_auth_backend.nomad_workloads.accessor
  }))
}

# ── Static policies owned by this module ─────────────────────────────────────
# Colocated in policies/ because they're an implementation detail of a role
# configured through this module and nothing outside references them (e.g.
# raft-snapshots, used only by the raft-snapshotter role below). A role opts in
# by filename via roles[*].owned_policies. Same file-per-policy convention as the
# root policies.tf; chomp() to match Vault stripping trailing whitespace.
resource "vault_policy" "owned" {
  for_each = fileset("${path.module}/policies", "*.hcl")

  name   = trimsuffix(each.value, ".hcl")
  policy = chomp(file("${path.module}/policies/${each.value}"))
}

# ── The roles ────────────────────────────────────────────────────────────────
# One role per distinct policy set. Nomad's bare vault{} blocks resolve to
# default_role (nomad-workloads); a job that names a different role (e.g. the
# raft snapshotter) selects it explicitly. Roles that set include_templated_policy
# get the accessor-templated policy above prepended to their token_policies
# (the default role's per-workload KV scope); everything else is passed in by
# reference from policies.tf, so roles order after those policies exist.
#
# Tokens are PERIODIC (token_period set, token_ttl/token_max_ttl left 0): Nomad
# renews them on the period for the alloc's life and derives a fresh one on
# restart. No hard cap — a periodic token renews indefinitely, which is what a
# long-running alloc needs. (Vault tokens are renewable, so unlike the Consul WI
# method a cap wouldn't silently kill an alloc — we simply don't need one.)
resource "vault_jwt_auth_backend_role" "this" {
  for_each = var.roles

  backend   = vault_jwt_auth_backend.nomad_workloads.path
  role_name = each.key
  role_type = "jwt"

  bound_audiences = [var.bound_audience]

  # Optional per-role claim gate. user_claim below only NAMES the entity; it does
  # not restrict which job may log in, so a privileged role (e.g. raft-snapshotter)
  # is assumable by any workload until bound_claims pins it to a specific job id.
  # Left null on unbound roles (the default catch-all) → no restriction.
  bound_claims      = each.value.bound_claims
  bound_claims_type = each.value.bound_claims_type

  # Identify the workload by job id. json_pointer because the claim is top-level
  # `nomad_job_id`; the leading "/" is the pointer, not a nested path.
  user_claim              = "/nomad_job_id"
  user_claim_json_pointer = true

  # Copied onto entity-alias metadata so the templated nomad-workloads policy can
  # interpolate them (namespace + job scope each token to its own KV subtree).
  claim_mappings = {
    nomad_namespace = "nomad_namespace"
    nomad_job_id    = "nomad_job_id"
    nomad_task      = "nomad_task"
  }

  token_type = "service"
  token_policies = concat(
    each.value.include_templated_policy ? [vault_policy.nomad_workloads.name] : [],
    [for f in each.value.owned_policies : vault_policy.owned[f].name],
    each.value.token_policies,
  )
  token_period = var.token_period_seconds
}
