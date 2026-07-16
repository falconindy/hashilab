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

## Rotate the pki_int / pki_int_internal intermediate CAs

Rotates the intermediate CA certs themselves — the certs `pki` (the root)
issues to `pki_int` and `pki_int_internal`. These are 5-year-TTL CA certs with
no automatic renewal, so rotating one is a manual, live-cluster procedure.
(Leaf certs issued _by_ those intermediates — Traefik's `*.service.home`
certs, the Consul/Nomad/Vault/omada-controller daemon certs — already
auto-rotate on their own and aren't covered here.)

The root (`pki`)'s own cert is also out of scope: it's the trust anchor baked
into `/etc/ssl/certs/home.pem` on every node, `bootstrap`-gated in tofu, and
rotating it means re-establishing trust fleet-wide — not something this entry
covers.

tofu only ever touches an intermediate's cert as a one-shot bootstrap action
(`vault_pki_secret_backend_intermediate_cert_request` →
`..._root_sign_intermediate` → `..._intermediate_set_signed`, gated by
`var.bootstrap`) — after bootstrap it's never touched again, and it's not in
`tofu/README.md`'s import list either. Live rotation replays that chain by
hand, against the mount's existing role/config which tofu still owns.

Do this for the 5-year TTL running out, or a suspected intermediate-key
compromise — not routine. Pick the mount and repeat for the other if needed;
they're independent.

```bash
export VAULT_ADDR=https://vault.service.home:8200
mount=pki_int_internal   # or pki_int
cn="home Vault Intermediate Authority [Internal]"  # match main.tf's common_name for the mount

# Preflight: note the current default issuer so you can tell old from new.
vault read -field=default "$mount/config/issuers"

# 1. New intermediate keypair + CSR. Private key never leaves Vault.
vault write -format=json "$mount/intermediate/generate/internal" \
  common_name="$cn" | jq -r .data.csr > /tmp/$mount.csr

# 2. Root signs it, off the same issuer tofu used (root_issuer_name, "root-2026").
vault write -format=json pki/issuer/root-2026/sign-intermediate \
  csr=@/tmp/$mount.csr format=pem_bundle ttl=43800h \
  | jq -r .data.certificate > /tmp/$mount.new.pem

# 3. Import — adds a NEW issuer alongside the old one, does not replace it.
vault write -format=json "$mount/intermediate/set-signed" \
  certificate=@/tmp/$mount.new.pem | tee /tmp/$mount.import.json
new_issuer=$(jq -r '.data.imported_issuers[0]' /tmp/$mount.import.json)

# GATE: confirm the new issuer looks right before cutting over.
vault read "$mount/issuer/$new_issuer"

# 4. Cut new leaf/ACME issuance over to it.
vault write "$mount/config/issuers" default="$new_issuer"
```

Nothing on any node needs to change: `/etc/ssl/certs/home.pem` is only the
root, and leaf certs bundle whichever intermediate actually issued them — old
leaves stay valid as long as the old issuer is still present in the mount.
Existing leaf certs roll onto the new intermediate as they naturally renew
(vault-agent's 32-day lease cycle, Traefik's ACME renewal) — no forced action
needed.

**Cleanup ordering:** leave the old issuer in the mount until every leaf cert
that could have been signed by it has since rotated — a full 32-day cycle plus
margin, tracked per node/service rather than assumed. Only then:

```bash
vault delete "$mount/issuer/<old-issuer-id>"
```

Deleting a still-referenced issuer breaks every leaf cert it signed — the same
"clean rollback into an outage" trap as the Connect CA cleanup below.

## Migrate Consul Connect to the Vault CA provider

Switches Connect's mesh CA from the built-in provider (root key in Consul's Raft)
to Vault (`pki` root + the `pki_int_connect` intermediate Consul manages). The
Vault side is tofu (`module.vault_pki_int_connect`); this is the live-cluster
cutover, which is **not** a tofu resource — editing `server.hcl` alone does
nothing on a running cluster (Consul reads `ca_config` from the agent file only
at first bootstrap; after that the CA config lives in Consul state and changes
only via `consul connect ca set-config`).

Prereqs: `tofu apply` has created the mount/policy/role and stashed `role_id`;
the consul role has been deployed so `server.hcl` carries the matching block (so
a rebuilt server comes up on Vault too). Do the cutover in a maintenance window.

```bash
supercow                                  # CONSUL_HTTP_TOKEN = mgmt, VAULT_TOKEN set
export CONSUL_HTTP_ADDR=https://consul.service.home:8501
export CONSUL_CACERT=/etc/ssl/certs/home.pem

# The CA CLI is only get-config/set-config — the roots live on the HTTP API.
# Helper to list them (which root is Active + what's still in the trust bundle):
ca_roots() { curl -s --cacert "$CONSUL_CACERT" -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
  "$CONSUL_HTTP_ADDR/v1/connect/ca/roots" | jq '{ActiveRootID, Roots: [.Roots[] | {Name, Active}]}'; }

# Pre-flight — capture the rollback target and a safety net.
consul connect ca get-config > /tmp/ca-config.before.json   # the built-in config, verbatim
consul snapshot save connect-ca-preflight.snap
ca_roots                                                     # note the current Active root

# Build the Vault provider config. role_id is the one tofu stashed.
role_id=$(vault kv get -field=role_id kv/consul/connect-ca)
cat > /tmp/ca-config.vault.json <<EOF
{
  "Provider": "vault",
  "Config": {
    "Address": "https://vault.service.home:8200",
    "RootPKIPath": "pki/",
    "IntermediatePKIPath": "pki_int_connect/",
    "AuthMethod": {
      "Type": "approle",
      "MountPath": "approle",
      "Params": { "role_id": "$role_id" }
    }
  }
}
EOF

consul connect ca set-config -config-file=/tmp/ca-config.vault.json

# GATE: the Vault-issued root is now Active, and the old built-in root is still
# in the trust bundle (cross-signed) so existing leaf certs stay valid.
ca_roots                              # Vault root Active=true; built-in root still listed (Active=false)
consul connect ca get-config          # Provider = vault
```

Then watch Envoy/xDS settle across the fleet (this is the same failure surface as
the WI-token TTL incident — leaf issuance breaking shows up as xDS "ACL not
found" churn). Consul cross-signs the new intermediate from the old CA, so a
healthy cutover is zero-downtime.

### Rollback

The Vault-side `tofu apply` is inert until the cutover points Consul at it, so
before the `set-config` there's nothing to undo. After it, replay the captured
built-in config:

```bash
supercow
consul connect ca set-config -config-file=/tmp/ca-config.before.json
ca_roots                              # built-in root Active again; Vault root still listed (Active=false)
```

This cross-signs the returning built-in root **from the currently-active Vault
CA**, so it's zero-downtime _as long as Vault is reachable_. If you're rolling
back because Vault is down, cross-signing isn't possible — force it, accepting a
brief mesh-wide disruption until every proxy has the new root:

```bash
consul connect ca set-config -config-file=/tmp/ca-config.before.json -force-without-cross-signing
```

`consul snapshot restore connect-ca-preflight.snap` is the last resort — it
rewinds **all** Consul state, not just the CA, so reserve it for a wedged control
plane.

**Vault cleanup ordering:** after a rollback, leave `pki_int_connect` and the
`consul-connect-ca` role/policy in place until `ca_roots` no longer lists the
Vault root (it drops out once its leaf certs have rotated away). Only then `tofu
destroy` the module — deleting the mount while its certs are still in the trust
bundle turns a clean rollback into an outage.
