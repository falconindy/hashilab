# ── ACL policies ─────────────────────────────────────────────────────────────
# One resource per policy file — policies/{vault,nomad}/*.hcl are the source of
# truth for the cross-cutting/human-facing policies (currently just `admin`, on
# Vault and Nomad). Keyed on filename; add or remove a file to add or remove the
# policy, and the policy name is the filename minus the extension. (A policy
# that's an implementation detail of one module lives in that module's own
# policies/ dir and is owned there instead — see the modules.)
#
# There's deliberately no Consul equivalent: Consul's admin is the built-in
# `global-management`, delivered to humans as an ephemeral token via the Vault
# Consul secrets engine + bin/supercow, so there are no root-level Consul policy
# files to reconcile. Every Consul policy is module-owned (modules/consul/*).
#
# tofu only manages — and only deletes — the policies backed by a file here.
# Built-ins (Vault `default`/`root`, Nomad `anonymous`, Consul
# `global-management`) aren't file-backed, so tofu never touches them. A policy
# created out of band is likewise left alone.
#
# Trailing-whitespace handling differs by backend: Vault strips it from stored
# policies, so chomp() the file to match (else a phantom trailing-newline diff
# every plan); Nomad stores verbatim, so pass the file through unchanged.

locals {
  # Per-file Nomad policy descriptions; falls back to a generic one below.
  nomad_policy_descriptions = {
    "admin.hcl" = "day-to-day admin"
  }
}

resource "vault_policy" "this" {
  for_each = fileset("${path.module}/policies/vault", "*.hcl")

  name   = trimsuffix(each.value, ".hcl")
  policy = chomp(file("${path.module}/policies/vault/${each.value}"))
}

resource "nomad_acl_policy" "this" {
  for_each = fileset("${path.module}/policies/nomad", "*.hcl")

  name        = trimsuffix(each.value, ".hcl")
  rules_hcl   = file("${path.module}/policies/nomad/${each.value}")
  description = lookup(local.nomad_policy_descriptions, each.value, "Managed by tofu from policies/nomad/${each.value}")
}
