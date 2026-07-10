# RUNBOOK

Break-glass and incident procedures for the homelab. Keep this readable without
a working cluster — during an incident the fancy tooling may be what's broken.

## Regenerate a Vault root token

Vault uses **GCP KMS auto-unseal** with **Shamir recovery keys** (`gcpckms`
seal, recovery threshold **3 of 5**). The root token is normally revoked; this
ceremony reconstructs one on demand. It is authorized by the **recovery keys**,
not unseal keys, and runs **unauthenticated** — that's the point of break-glass.

Prerequisite: 3 of the 5 recovery shares, retrievable offline. If those are
lost, root is unrecoverable. Auto-unseal means you never otherwise touch these
keys, so periodically confirm they still exist and are readable.

```bash
export VAULT_ADDR=https://vault.service.home:8200

# 1. Start the ceremony. Note the printed Nonce and OTP.
vault operator generate-root -init

# 2. Submit recovery shares against that nonce until 3 are in. Each holder runs
#    this on their own machine; solo, run it three times with a different share
#    each time. The third submission prints an "Encoded Token".
vault operator generate-root -nonce=<nonce>   # paste a recovery key when prompted

# 3. Decode the encoded token with the OTP from step 1 to get the real token.
vault operator generate-root -decode=<encoded-token> -otp=<otp>
```

When done with whatever required root, **revoke it again** — root tokens have no
TTL, and a forgotten one is the liability this setup exists to avoid:

```bash
vault token revoke <token>
```

Useful around the edges:

- `vault operator generate-root -status` — inspect an in-progress ceremony.
- `vault operator generate-root -cancel` — abort. Always cancel a botched
  attempt before re-running `-init`; a stale ceremony rejects a fresh start.
- `vault operator generate-root -init -pgp-key=keybase:<user>` — encrypt the
  encoded token to a PGP key instead of using an OTP; decrypt with `gpg`.

Day-to-day admin access does not use root — see [OIDC login](#) via Pocket-ID
(`bin/vault-build-oidc`) and the `admin` policy (`admin.hcl`).

## Rotate a gossip encryption key (Consul or Nomad)

Serf gossip is encrypted with a single **symmetric key shared by every agent** in a
pool — for Consul, every agent (servers, Debian clients, the NAS); for Nomad, only the
servers gossip. Unlike the TLS certs it is not per-node and not reissued: it's rotated
in place through the **keyring**, which holds several keys at once so the pool can
decrypt both old and new traffic during the change. The live key lives in each agent's
persisted keyring (`data_dir/serf/`) and propagates over gossip.

The `encrypt = "..."` line in config is the **current primary, read from Vault KV**
(`kv/consul/gossip`, `kv/nomad/gossip`) by Ansible at deploy time. But **running agents
ignore it** — the persisted keyring is authoritative once initialized; `encrypt` only
seeds a from-scratch agent. Two consequences:

- **Rotating the running fleet is the keyring ceremony below, not an Ansible run.**
- You `vault kv put` the new key as _part of_ that ceremony, so the next from-scratch
  node bootstraps on the current key. Keep Vault equal to the live primary.

You rarely need this — a suspected key exposure, or periodic hygiene. `bin/supercow`
drops you in a subshell holding both the Consul and Nomad management tokens the keyring
ops require.

### Consul

```bash
export CONSUL_HTTP_ADDR=https://consul.service.home:8501
export CONSUL_CACERT=/etc/ssl/certs/home.pem

old=$(vault kv get -field=key kv/consul/gossip)   # capture before overwriting
new=$(consul keygen)
vault kv put kv/consul/gossip key="$new"          # so future from-scratch nodes bootstrap on it

consul keyring -install "$new"   # add to every agent's keyring (not yet primary)
consul keyring -list             # GATE: every key at [N/N] per pool before continuing
consul keyring -use "$new"       # make it primary (agents encrypt outbound with it)
consul keyring -remove "$old"    # drop the old key everywhere
consul keyring -list             # confirm one key, at [N/N]
```

### Nomad

Only the servers gossip. Same shape, using the `NOMAD_TOKEN` supercow also set:

```bash
old=$(vault kv get -field=key kv/nomad/gossip)
new=$(nomad operator gossip keyring generate)   # same key format as consul keygen
vault kv put kv/nomad/gossip key="$new"

nomad operator gossip keyring install "$new"
nomad operator gossip keyring list              # GATE: all servers hold it
nomad operator gossip keyring use "$new"
nomad operator gossip keyring remove "$old"
nomad operator gossip keyring list
```

Safety notes:

- **Never `remove` until `list` shows the new key at full count in every pool.** The
  keyring reaches agents over gossip, so an unreachable one silently misses the install
  and drops out when the old key goes. Re-run `install` to re-add it first.
- No per-node SSH is needed — keyring changes propagate through the mesh, the NAS
  included. Consul runs a single `global` datacenter (one LAN pool, no separate WAN).
- **The Vault write is not the rotation.** Writing `kv/*/gossip` and re-deploying config
  does not re-key running agents (they ignore `encrypt`) — the keyring ceremony does.
  Conversely, a _new_ node now joins with no manual step: Ansible renders the live key.
- The next `ansible-playbook` run renders the new `encrypt` and, because the value
  changed, flags a Consul/Nomad rolling restart. It's harmless (the keyring already
  rotated) — run it at leisure or skip it.

First-time setup (before the roles can render these): seed each secret with the current
live primary and bound its history —
`vault kv put kv/consul/gossip key=<current>` (likewise `kv/nomad/gossip`), then
`vault kv metadata put -max-versions=3 kv/consul/gossip` (likewise Nomad).
