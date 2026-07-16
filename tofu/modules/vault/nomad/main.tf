# ── The dedicated Nomad management token ─────────────────────────────────────
# The engine authenticates to Nomad with its own dedicated management token
# rather than a shared one. tofu owns exactly one token in state, so rotation and
# pruning are automatic — re-applying with a change rotates it and Nomad deletes
# the superseded one. Creating this requires NOMAD_TOKEN to be a *management*
# token (see providers.tf).
resource "nomad_acl_token" "engine" {
  name   = var.engine_token_name
  type   = "management"
  global = true
}

# Reads back the secret_id for the engine token without persisting it to state.
ephemeral "nomad_acl_token" "engine" {
  accessor_id = nomad_acl_token.engine.accessor_id
}

# ── The secrets engine ───────────────────────────────────────────────────────
# The engine authenticates to Nomad with the dedicated token above — NOT the
# bootstrap token — so the bootstrap token can be retired afterwards without
# killing the engine. ttl/max_ttl write nomad/config/lease (the creds lease that
# governs how long a minted token lives), which the vault provider also keys the
# backend's existence on — so managing it here means the endpoint always exists
# (so an import finds it already present). We deliberately do NOT
# set default_lease_ttl_seconds/max_lease_ttl_seconds; those are the *mount* tune
# and we leave the mount's existing values alone.
resource "vault_nomad_secret_backend" "nomad" {
  backend          = var.backend
  address          = var.nomad_address
  token_wo         = ephemeral.nomad_acl_token.engine.secret_id
  token_wo_version = 1
  ttl              = var.creds_ttl_seconds
  max_ttl          = var.creds_max_ttl_seconds
  description      = "Mints short-lived, lease-bound Nomad management tokens on demand."
}

# ── The mgmt role ────────────────────────────────────────────────────────────
# Equivalent to `vault write nomad/role/mgmt type=management global=true`. This is the
# break-glass path for Nomad ACL administration, which no ACL *policy* can grant.
resource "vault_nomad_secret_role" "mgmt" {
  backend = vault_nomad_secret_backend.nomad.backend
  role    = var.role_name
  type    = "management"
  global  = true
}
