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

The root (`pki`)'s own cert is a separate, larger-blast-radius operation —
it's the trust anchor baked into `/etc/ssl/certs/home.pem` on every node, so
rotating it means re-establishing trust fleet-wide. See [Rotate the pki root
CA (cross-signing)](#rotate-the-pki-root-ca-cross-signing) below.

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

## Rotate the pki root CA (cross-signing)

The larger-blast-radius sibling of the above: `pki`'s own root cert, not just
what it signs. 10-year TTL, and it's the trust anchor baked into
`/etc/ssl/certs/home.pem` on every node (via the `trust` role), so a naive
swap invalidates every mTLS handshake fleet-wide the instant it lands. **Cross-
signing decouples "generate the new root" from "everyone trusts it"**: the
intermediates keep their existing keys and just pick up a second signature
from the new root, so leaf certs already issued (and the leaf-issuing keys
themselves) are untouched throughout — you control the fleet-wide trust
rollout and the cutover as two separate, reversible steps instead of one
flag day. Rare — a root nearing its 10-year TTL, or a suspected root-key
compromise.

`pki_int_connect` (Consul's mesh CA intermediate) isn't rotated by this
procedure the way `pki_int`/`pki_int_internal` are — but it's not immune to
it either. Consul's Vault CA provider config (see [Migrate Consul Connect to
the Vault CA provider](#migrate-consul-connect-to-the-vault-ca-provider)
below) has no pinned `issuer_ref`: `RootPKIPath: "pki/"` means Consul always
signs its intermediate against whatever `pki`'s **current default issuer**
is at request time. So flipping that default — the root mount's own
`config/issuers` write, down in cleanup below — silently changes what
Consul gets _the next time it rotates its own intermediate_, on Consul's
own schedule, using Consul's own internal cross-sign (old intermediate →
new intermediate) for sidecar continuity — a separate mechanism from the
Vault-level cross-sign this procedure does for `pki_int`/`pki_int_internal`.
Mesh trust itself is unaffected by the fleet trust-store staging below —
sidecars trust whatever Consul's own Connect CA roots API serves them, not
`/etc/ssl/certs/home.pem` — but don't leave the pickup to chance: the
cleanup step forces and confirms it explicitly.

```bash
export VAULT_ADDR=https://vault.service.home:8200

# 1. New root, in the SAME pki mount — multi-issuer, doesn't touch root-2026.
#    Distinct common_name/issuer_name so the two are unmistakable side by side.
#    This is NOT the endpoint tofu's bootstrap resource uses (that one assumes
#    a green-field mount); this is the add-a-second-root path.
vault write pki/issuers/generate/root/internal \
  common_name="home 2031" issuer_name="root-2031" ttl=87600h
```

```bash
# 2. Cross-sign each intermediate's EXISTING cert under the new root — same
#    key (key_ref), same subject, just a second signature. Repeat per mount.
mount=pki_int_internal   # or pki_int
cn="home Vault Intermediate Authority [Internal]"   # main.tf's common_name — must match exactly

old_issuer=$(vault read -field=default "$mount/config/issuers")
key_ref=$(vault read -field=key_id "$mount/issuer/$old_issuer")

vault write -format=json "$mount/intermediate/cross-sign" \
  key_ref="$key_ref" common_name="$cn" | jq -r .data.csr > /tmp/$mount.xsign.csr

vault write -format=json pki/issuer/root-2031/sign-intermediate \
  csr=@/tmp/$mount.xsign.csr format=pem_bundle ttl=43800h \
  | jq -r .data.certificate > /tmp/$mount.xsign.pem

vault write -format=json "$mount/intermediate/set-signed" \
  certificate=@/tmp/$mount.xsign.pem | tee /tmp/$mount.xsign-import.json
new_issuer=$(jq -r '.data.imported_issuers[0]' /tmp/$mount.xsign-import.json)

# Vault won't detect a cross-signed pair on its own — tell it about both paths.
vault patch "$mount/issuer/$old_issuer" manual_chain=self,root-2026,"$new_issuer",root-2031
vault patch "$mount/issuer/$new_issuer" manual_chain=self,root-2031,"$old_issuer",root-2026
```

```bash
# GATE: confirm both chains verify before anything client-facing changes.
vault pki verify-sign pki/issuer/root-2031 "$mount/issuer/$new_issuer"   # new pair
vault pki verify-sign pki/issuer/root-2026 "$mount/issuer/$old_issuer"   # old pair, unchanged
```

Roll trust out to the fleet **before** cutting anything over. The `trust`
role only ever syncs the mount's _current default_ issuer (`pki/cert/ca`), so
mid-rotation you stage both roots into `home.crt` by hand — Debian's local-CA
mechanism accepts multiple concatenated PEM certs in one file:

```bash
vault read -field=certificate pki/issuer/root-2026 >  /tmp/home-dual.crt
vault read -field=certificate pki/issuer/root-2031 >> /tmp/home-dual.crt

ansible all:\!synology -i inventory/hosts.yml -m ansible.builtin.copy \
  -a "src=/tmp/home-dual.crt dest=/usr/local/share/ca-certificates/home.crt mode=0644" --become
ansible all:\!synology -i inventory/hosts.yml -m ansible.builtin.command \
  -a "update-ca-certificates" --become
```

`nasty` needs the same treatment through its own path — `roles/synology/tasks/
main.yml` renders a single-issuer `home-ca.pem` the same way the `trust` role
does; push the dual-cert bundle there by hand too (its role has the same
one-issuer limitation).

Once every node trusts both roots, cut new leaf/ACME issuance over to the
cross-signed intermediate:

```bash
vault write "$mount/config/issuers" default="$new_issuer"
```

Existing leaf certs are unaffected (same intermediate key underneath either
cert) and roll onto the new chain as they naturally renew — same as
intermediate rotation, no forced action needed.

**Cleanup, once every leaf has cycled onto the new chain** (a full 32-day
cycle plus margin) **and `home.crt` has been rolled back to just root-2031**
(re-run the `trust` role — it'll now pick up `pki/cert/ca` = root-2031 on its
own):

```bash
vault write pki/config/issuers default=root-2031   # root mount's own default
```

This is also the point where `pki_int_connect` picks up the new root — see
the caveat above. Don't leave that to Consul's own timing; force it and
check before going further:

```bash
supercow   # CONSUL_HTTP_TOKEN = mgmt
export CONSUL_HTTP_ADDR=https://consul.service.home:8501
export CONSUL_CACERT=/etc/ssl/certs/home.pem

# Re-apply the SAME provider config Consul already has — forces it to
# regenerate its intermediate now, against pki's new default, instead of
# whenever it next decides to on its own.
consul connect ca get-config > /tmp/ca-config.current.json
consul connect ca set-config -config-file=/tmp/ca-config.current.json

# GATE: the new pki_int_connect intermediate (signed under root-2031) is
# Active; Consul's own cross-signed prior intermediate is still listed so
# in-flight sidecars aren't broken mid-rollout.
curl -s --cacert "$CONSUL_CACERT" -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
  "$CONSUL_HTTP_ADDR/v1/connect/ca/roots" | jq '{ActiveRootID, Roots: [.Roots[] | {Name, Active}]}'
```

Only once that settles — the mesh no longer needs `root-2026` — is it safe
to remove it:

```bash
vault delete "$mount/issuer/$old_issuer"   # the pre-rotation pki_int/pki_int_internal cert
vault delete pki/issuer/root-2026          # the old root itself
```

Same "clean rollback into an outage" trap as the intermediate cleanup above:
don't delete an issuer anything might still be presenting.

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
