# Known Issues

Homelab bugs and gaps that are understood but not (yet) worth fixing, working
around, or that depend on an upstream fix. Not a place for routine bugs —
those get fixed. This is for things where the root cause is external or the
fix isn't worth the effort right now.

## Consul streaming health subscriptions wedge with "ACL not found" after a server's cert reloads

Symptom: a Consul client agent (seen on `nomad0`) logs a growing stream of

```
agent.rpcclient.health: subscribe call failed: err="rpc error: code = Unknown desc = ACL not found" failure_count=<N> key=<service> topic=ServiceHealth
```

across many unrelated services simultaneously, each with a rising
`failure_count`. It does not self-heal — it persists until the affected
agent's Consul process is restarted (`consul reload` on the wedged node does
**not** clear it; only a full restart does).

**Trigger**: `os/etc/vault-agent.d/consul-tls.hcl` renews a Consul server's
TLS cert from Vault PKI and runs `systemctl reload consul` on that server via
its `exec` hook — routine, roughly every ~16 days per node since
`f8cfbf9` lowered `lease_renewal_threshold` to 0.5. Observed once so far:
`nomad2` reloaded at `13:04:25` on 2026-07-20 (cert renewal from the
`lease_renewal_threshold` change committed at `13:05:08` the same day);
`nomad0` started logging the failure ~9 minutes later and didn't recover
until its Consul process was restarted.

**Why**: confirmed by reading Consul's source (`tlsutil/config.go`) that the
leaf-cert hot-swap itself (`GetCertificate` closure, read only during a TLS
handshake) cannot affect an already-established gRPC connection — so this
isn't a torn-down connection. The likelier mechanism: `consul reload`
(`agent/agent.go` `reloadConfigInternal`) is one atomic operation on the
reloaded server — pausing sync, unloading/reloading every local service,
check, and watch, reloading ACL token config — and a remote streaming
subscription's RPC that happens to land inside that window can get back a
spurious "not found." Once that happens, the client-side subscription code
doesn't recover on its own; it just keeps replaying the same failed
resolution (matches upstream [hashicorp/consul#22515]
(https://github.com/hashicorp/consul/issues/22515), which reports the
identical log signature from a different trigger — Nomad revoking a
workload's ACL token on alloc stop — so the "subscription never recovers
from one ACL-not-found" behavior looks like a general client-side bug, not
specific to our TLS-reload trigger).

Sporadic because it needs: the subscription pinned to the one server (of 3)
that's mid-reload at that moment, the RPC landing inside the brief
inconsistent-state window, and then hitting the non-recovering retry bug —
most reloads on most nodes produce no visible symptom.

**Workaround**: restart Consul on any client agent logging this
(`systemctl restart consul`) — reload is not sufficient.

**Not planned**: no known way to prevent the underlying race from our side
(other than not rotating certs, which isn't acceptable), and the failure to
recover is an upstream client behavior. Revisit if hashicorp/consul#22515
lands a fix, or if this becomes frequent enough to script a health-log watch
that auto-restarts affected agents.
