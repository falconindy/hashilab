# nomad-admin.hcl — broad day-to-day Nomad ACL policy for the solo sysadmin.
#
# Attach to a client token (or an OIDC binding rule) instead of carrying the
# static bootstrap token.
#
# IMPORTANT: this is NOT root-equivalent. In Nomad, ACL administration —
# creating tokens, writing policies, managing auth methods and binding rules —
# requires a *management* token and cannot be granted by any policy. This covers
# every day-to-day workload and cluster operation but not ACL management itself.
# Keep a management token as break-glass for that, or bind your OIDC login with
# `-bind-type=management` to get the full equivalent.
#
# Apply with:
#   nomad acl policy apply -description "day-to-day admin" admin nomad-admin.hcl

# Full control over jobs, allocs, logs, exec, and Nomad variables in every
# namespace. `policy = "write"` already grants submit-job, dispatch, read-logs,
# alloc-exec, alloc-lifecycle, scaling, and CSI volume use; alloc-node-exec is
# additive (exec into raw_exec/host tasks).
namespace "*" {
  policy       = "write"
  capabilities = ["alloc-node-exec"]

  variables {
    path "*" {
      capabilities = ["list", "read", "write", "destroy"]
    }
  }
}

# Drain/eligibility and client lifecycle.
node {
  policy = "write"
}

node_pool "*" {
  policy = "write"
}

# Agent endpoints (force-leave, gossip keyring, runtime profiles).
agent {
  policy = "write"
}

# Operator endpoints (autopilot, raft, scheduler config, snapshots).
operator {
  policy = "write"
}

# CSI plugin status.
plugin {
  policy = "read"
}

# Dynamic host volumes.
host_volume "*" {
  policy = "write"
}
