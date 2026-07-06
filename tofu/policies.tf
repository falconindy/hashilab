# ── ACL policies ─────────────────────────────────────────────────────────────
# One resource per policy file — vault/policies/*.hcl, nomad/policies/*.hcl and
# consul/policies/*.hcl are the source of truth. Keyed on filename; add or remove
# a file to add or remove the policy, and the policy name is the filename minus
# the extension.
#
# tofu only manages — and only deletes — the policies backed by a file here.
# Built-ins (Vault `default`/`root`, Nomad `anonymous`, Consul
# `global-management`) aren't file-backed, so tofu never touches them. A policy
# created out of band is likewise left alone.
#
# Trailing-whitespace handling differs by backend: Vault strips it from stored
# policies, so chomp() the file to match (else a phantom trailing-newline diff
# every plan); Nomad and Consul store verbatim, so pass the file through
# unchanged.

locals {
  # Per-file Nomad policy descriptions; falls back to a generic one below.
  nomad_policy_descriptions = {
    "admin.hcl" = "day-to-day admin"
  }
}

resource "vault_policy" "this" {
  for_each = fileset("${path.module}/../vault/policies", "*.hcl")

  name   = trimsuffix(each.value, ".hcl")
  policy = chomp(file("${path.module}/../vault/policies/${each.value}"))
}

resource "nomad_acl_policy" "this" {
  for_each = fileset("${path.module}/../nomad/policies", "*.hcl")

  name        = trimsuffix(each.value, ".hcl")
  rules_hcl   = file("${path.module}/../nomad/policies/${each.value}")
  description = lookup(local.nomad_policy_descriptions, each.value, "Managed by tofu from nomad/policies/${each.value}")
}

resource "consul_acl_policy" "this" {
  for_each = fileset("${path.module}/../consul/policies", "*.hcl")

  name  = trimsuffix(each.value, ".hcl")
  rules = file("${path.module}/../consul/policies/${each.value}")
}
