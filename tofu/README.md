# tofu/ — declarative Vault + Nomad + Consul control plane

OpenTofu configuration that manages the Vault, Nomad and Consul control plane
declaratively: the PKI engines, the SSH client CA, OIDC login for both Vault and
Nomad, the Vault→Nomad and Vault→Consul secrets-engine integrations, and the
Consul ACL layer (policies, the anonymous/daemon tokens, and the Nomad
workload-identity auth method). State tracking gives idempotence and drift
detection; the key-generating steps are fenced behind a `bootstrap` flag so
day-to-day runs can't regenerate a live CA.

Modules are grouped by provider under `modules/<provider>/` and the block labels
carry the same namespace (`module.vault_pki`, `module.vault_ssh`, …) so
Nomad- and Consul-side modules don't collide with Vault ones. It's a real
collision, not hypothetical: the Vault Nomad _secrets engine_ is
`modules/vault/nomad`, while Nomad's own OIDC login is `modules/nomad/oidc` —
without the namespace both would just be "nomad". Likewise the Vault Consul
_secrets engine_ (`modules/vault/consul`) vs. the Consul-provider ACL modules
(`modules/consul/*`).

## Modules

Four PKI engines:

- `modules/vault/pki` — the self-signed root CA (`home`, 10y): the `pki` mount,
  the self-signed root, `config/cluster`, `config/urls`, and the `servers` role.
- `modules/vault/pki_int` — the ACME intermediate: the `pki_int` mount (+ ACME
  header tuning), the CSR → root-sign → import chain, `config/cluster`,
  `config/urls`, the `intermediate` role, and `config/acme`.
- `modules/vault/pki_int_internal` — the internal-client-cert intermediate: same
  shape as `pki_int` but no ACME, and its `intermediate` role sets
  `no_store=true` with a longer `max_ttl` (4380h).
- `modules/vault/pki_int_connect` — the Consul Connect mesh CA. **Different shape
  from the other intermediates: Consul, not tofu, generates the intermediate,
  gets `pki` to sign it, and rotates all mesh leaf certs.** So there's no
  CSR/sign/import chain and no `bootstrap` gate here — the module only reserves
  the empty `pki_int_connect` mount, owns the least-privilege `consul-connect-ca`
  policy, and creates a keyless AppRole role (`consul-connect-ca`) on the existing
  `approle` mount, stashing its `role_id` in Vault KV (`kv/consul/connect-ca`) for
  the consul Ansible role. The Consul-side provider switch is applied out of band
  ("Migrate Consul Connect to the Vault CA provider" in `RUNBOOK.md`), not by a
  tofu resource.

The root config (`main.tf`) wires them together: both signing intermediates'
`root_issuer_ref` is fed from `module.vault_pki.issuer_name`, so the chain is
explicit.

The SSH client-cert CA:

- `modules/vault/ssh` — the `ssh-client-signer` mount, the CA signing keypair, and
  the `admin` signing role. (Signing is authorized by the `admin` Vault policy,
  which has `path "*"`; there's no dedicated lower-privilege SSH-signing policy.)

Vault OIDC login:

- `modules/vault/oidc` — the `oidc` auth method (Pocket-ID discovery + client
  creds + `default_role`) and its `admin` role. This is an auth method, not a
  secrets engine: **no key material, so no `bootstrap` gate** — it's pure,
  idempotent config and always managed. The Pocket-ID client id/secret are the
  only inputs, passed in as sensitive variables (below).

Vault-agent AppRole:

- `modules/vault/approle` — the `approle` auth method + the `vault-agent` role
  every node's vault-agent logs in with (role_id only, `bind_secret_id=false`) to
  render its TLS certs. Pinned to the live role; import to adopt the existing
  `role_id` (shipped to hosts as a static file out of band).

The Vault Nomad secrets engine:

- `modules/vault/nomad` — the `nomad` secrets engine + `mgmt` (management) creds
  role, for minting break-glass Nomad management tokens. This is the one module
  that also drives the **Nomad provider**: minting a dedicated management token
  and pruning superseded ones is expressed as a single `nomad_acl_token` resource
  whose lifecycle tofu owns (rotate = re-apply, prune = automatic). Two
  consequences: it needs a Nomad **management** token in `NOMAD_TOKEN` (see
  below), and its `secret_id` lands in **tofu state** — so this module is the
  reason to protect state (encryption / secure backend; see `versions.tf`).

The Vault Consul secrets engine:

- `modules/vault/consul` — the `consul` secrets engine + `mgmt` creds role, for
  minting break-glass Consul management tokens (`vault read consul/creds/mgmt`,
  consumed by `bin/supercow`). A near-exact mirror of `modules/vault/nomad`:
  it owns a dedicated **Consul** management token (a `consul_acl_token` carrying
  the built-in `global-management` policy) and points `consul/config/access` at
  it, so the bootstrap token can be retired. That token's `secret_id` lands in
  **tofu state** — another reason to protect state. Needs a Consul management
  token in `CONSUL_HTTP_TOKEN` (see below).

The Nomad workload-identity flow into Vault:

- `modules/vault/nomad-wi` — the Vault-side twin of `modules/consul/nomad-wi`.
  The `jwt-nomad` JWT auth method and its roles (`nomad-workloads`, the default
  every bare `vault{}` block resolves to, plus `raft-snapshotter`). This is an
  auth method — **no key material, no `bootstrap` gate**. Must exist **before**
  Nomad's `vault{}` `default_identity` goes live (allocations begin their JWT
  login the moment a `vault{}` block deploys). Do not confuse with
  `modules/vault/nomad` above, which is the opposite direction (Vault minting
  Nomad tokens). Two things differ from the Consul method: Vault reads its
  **node-local** Nomad agent's JWKS (`https://localhost:4646/...`) and embeds **no
  CA** (validation rides the node's system trust store), where Consul uses the
  cluster DNS name with the home CA embedded. The `nomad-workloads` policy is
  **templated on the mount accessor** and owned by this module (rendered from
  `templates/nomad-workloads.hcl.tftpl` with the accessor read off the live
  resource), not a static policy file — a hand-copied accessor
  breaks silently when the mount is recreated. Roles opt in via
  `roles[*].include_templated_policy`. The module also owns the static
  `raft-snapshots` policy (`policies/raft-snapshots.hcl`, used only by the
  `raft-snapshotter` role, which opts in via `roles[*].owned_policies`); other
  policies come from `policies.tf` by reference (`token_policies`).

Nomad OIDC login:

- `modules/nomad/oidc` — the `pocket-id` OIDC auth method + the binding rule that
  maps everyone authenticating through it to the `admin` policy. Nomad-provider
  only; like the Vault OIDC module it's pure config with **no bootstrap gate**.
  Uses a **separate** Pocket-ID client from Vault (the "Nomad" client — different
  id/secret). The `admin` policy the rule binds to is managed centrally (see
  **Policies**). Applying it needs a Nomad **management** token (auth-method +
  binding-rule creation is ACL administration).

The Consul ACL layer (Consul provider — needs a Consul **management** token):

- `modules/consul/acl` — the baseline ACL identities, and it **owns the baseline
  policies** they carry (`policies/*.hcl` — `anonymous` plus the four daemon
  policies — since nothing outside this module consumes them). Attaches the
  `anonymous` policy to Consul's built-in anonymous token (what an unauthenticated
  request gets under `default_policy = "deny"` — keeps DNS, the dashboard, and
  Prometheus SD working with no token), and mints the four **non-expiring daemon
  tokens** (`consul-agent`, `consul-config-services`, `nomad-agent`,
  `vault-registration` — the `daemon_token_policy_files` default), stashing each
  in **Vault KV** (`kv/consul/tokens/<name>`) for the Ansible roles to template
  into config.
  Those are always-on daemon identities read once and never renewed, so they must
  not be leased — the dynamic/leased path is `modules/vault/consul`. Their
  `secret_id`s land in **tofu state** and KV.
- `modules/consul/nomad-wi` — the Nomad workload-identity flow into Consul: the
  `nomad-workloads` JWT auth method (trusts Nomad's JWKS, home CA embedded), the
  per-service + serviceless binding rules, and the `nomad-tasks` role. Must exist
  **before** Nomad's `consul{}` gets its `service_identity`/`task_identity`
  blocks (allocations start their JWT login the moment those deploy).
- `modules/consul/mesh` — the mesh **config entries**. Two things:
  - An empty `proxy-defaults/global`: the Connect/Envoy bootstrap path fetches
    `GET /v1/config/proxy-defaults/global` on every sidecar setup, and with no
    entry present Consul logs each miss as an `ERROR` on a loop. The entry turns
    those 404s into 200s to silence the noise — it tunes nothing. Real defaults
    (protocol, mesh-gateway mode, …) can go in its `config_json` later.
  - The **service intentions** (`intentions.tf`) — the mesh's L4 authorization,
    previously applied out of band with `consul config write`. The mesh is
    default-deny (`*`/`*` deny at precedence 5); every allowed edge is an explicit
    higher-precedence source. Keyed by destination in the `intentions` local (one
    `consul_config_entry_service_intentions.this[<dest>]` per key). `precedence`
    is Consul-computed but the provider marks it plain-optional, so the module
    recomputes the same value (9 exact-dest / 6 wildcard-dest, −1 for a `*`
    source) to keep plans from perpetually zeroing it. Adopt the live entries with
    `import` (below) — a fresh apply would try to create them and clash.

Policies:

- `policies.tf` (root) — reconciles Vault and Nomad ACL policies from
  `tofu/policies/{vault,nomad}/*.hcl`, one resource per file via `for_each`.
  The policy name is the filename minus `.hcl`; add or remove a file to add or
  remove the policy.
  tofu only deletes policies backed by a file here and never touches built-ins
  (`default`/`root`, Nomad `anonymous`, Consul `global-management`). A policy
  attached by exactly one module, as an implementation detail of it, is **owned by
  that module** instead (its `.hcl` lives in the module's `policies/` dir): the
  templated `nomad-workloads` + static `raft-snapshots` in `modules/vault/nomad-wi`,
  `internal-server-certs` in `modules/vault/approle`, the `anonymous` + daemon
  policies in `modules/consul/acl`, and the workload policies (`nomad-tasks`,
  `traefik`, `traefik-ingress`, `prometheus`) in `modules/consul/nomad-wi`. The
  only policy at the root is `admin` (a near-root policy for the solo sysadmin,
  attached to the OIDC login on both Vault and Nomad) — the one policy that is
  genuinely cross-cutting and not owned by a single module. There's **no root
  Consul policy list**: Consul's admin is the built-in `global-management`
  (delivered as an ephemeral token via `bin/supercow`), and every other Consul
  policy is module-owned.

## Auth

The providers read the environment:

```bash
vault login -method=oidc          # passkey -> admin token
export VAULT_ADDR=https://vault.service.home:8200
```

The two OIDC modules each need their own Pocket-ID client credentials (the Vault
client and the Nomad client are **separate** Pocket-ID clients). Rather than
retyping them, put them in a gitignored `secrets.auto.tfvars` — tofu auto-loads
it every run:

```bash
cp secrets.auto.tfvars.example secrets.auto.tfvars
chmod 600 secrets.auto.tfvars
$EDITOR secrets.auto.tfvars        # fill in the four values
```

Keep the canonical copy in your password manager — Pocket-ID shows a client
secret only once. The values also live in tofu state, so this file is no new
exposure; it's just a convenience + backup-of-record. See **OIDC credentials**
below for seeding/rotation.

The Nomad-provider modules (`vault_nomad` and `nomad_oidc`) need the Nomad
provider pointed at a **management** token — creating ACL tokens / auth methods
can't be done with the day-to-day OIDC admin token:

```bash
export NOMAD_ADDR=https://nomad.service.home:4646
export NOMAD_TOKEN=<a Nomad management token>   # break-glass / bootstrap token
```

The Consul-provider modules (`vault_consul`, `consul_acl`, `consul_nomad_wi`)
likewise need the Consul provider pointed at a **management** token — minting
tokens, policies, auth methods and binding rules is ACL administration. Use
`bin/supercow` (once the engine exists) or the bootstrap token during initial
bring-up. The provider parses the scheme from `CONSUL_HTTP_ADDR`; if yours lacks
it, also set `CONSUL_HTTP_SSL=true`:

```bash
export CONSUL_HTTP_ADDR=https://consul.service.home:8501
export CONSUL_CACERT=/etc/ssl/certs/home.pem
export CONSUL_HTTP_TOKEN=<a Consul management token>   # break-glass / bootstrap token
```

Chicken-and-egg on a cold start: Consul ACLs must be **enabled + bootstrapped**
first (out of band), and the bootstrap token seeds `CONSUL_HTTP_TOKEN` for the
initial apply. That apply builds the Consul secrets engine (which mints its own
dedicated management token) plus the daemon tokens, after which the bootstrap
token can be retired.

## OIDC credentials (seed once, rotate in Pocket-ID)

tofu configures the _consumer_ side of OIDC (Vault/Nomad reading the client
secret); it cannot mint the secret — Pocket-ID issues it and shows it once. So
if the current secret is lost, seeding the tofu-managed config means rotating in
Pocket-ID. The flow, for each of the "Vault" and "Nomad" clients:

1. In the Pocket-ID admin UI, open the client and **regenerate its secret**. Copy
   the new value.
2. Put it in `secrets.auto.tfvars` (and your password manager).
3. `tofu apply` — writes the new secret into the Vault/Nomad OIDC config, so both
   sides match again.
4. Verify the login still works (`vault login -method=oidc`,
   `nomad login -method=pocket-id`).

Neither Vault nor Nomad returns the client secret on read, so after an import the
first plan always shows the OIDC config wanting to (re)write the secret from your
tfvars — that's expected; it's how the value gets asserted.

## The `bootstrap` flag (the safety gate)

The key-generating resources — the root's self-sign, each intermediate's
CSR/root-sign/set-signed chain, and the SSH CA signing keypair — are the only
destructive-if-misapplied parts. They're gated behind `var.bootstrap`, **default
false**. So by default a plan/apply only manages mounts, roles, and config (all
idempotent, all importable) and can never propose minting a new root, re-signing
a live intermediate, or regenerating the SSH CA. Each would detonate trust across
the fleet (nodes trust the root at `/etc/ssl/certs/home.pem` and the SSH CA at
`/etc/ssh/trusted-user-ca-keys.pem`).

- Existing cluster: leave `bootstrap = false` and `import` (below).
- Green field: set `bootstrap = true` for the initial apply that mints the CAs.

## Green field (nothing exists yet)

One apply builds root then intermediate in dependency order:

```bash
tofu -chdir=tofu init
tofu -chdir=tofu plan  -var bootstrap=true
tofu -chdir=tofu apply -var bootstrap=true
```

After the CAs exist, drop the flag back to false for subsequent runs.

## Existing cluster — IMPORT, do not apply blind

These engines already exist and are trusted everywhere. With `bootstrap=false`
(the default) the key-generating resources aren't in the plan at all, so there's
no re-mint risk — but you still must import the mounts/roles/config so the plan
diffs against reality instead of proposing to create them:

```bash
cd tofu && tofu init

# ── root (pki) ──
tofu import 'module.vault_pki.vault_mount.pki' pki
tofu import 'module.vault_pki.vault_pki_secret_backend_config_cluster.this' pki/config/cluster
tofu import 'module.vault_pki.vault_pki_secret_backend_config_urls.this'    pki/config/urls
tofu import 'module.vault_pki.vault_pki_secret_backend_role.servers'        pki/roles/servers

# ── intermediate (pki_int) ──
tofu import 'module.vault_pki_int.vault_mount.pki_int' pki_int
tofu import 'module.vault_pki_int.vault_pki_secret_backend_config_cluster.this' pki_int/config/cluster
tofu import 'module.vault_pki_int.vault_pki_secret_backend_config_urls.this'    pki_int/config/urls
tofu import 'module.vault_pki_int.vault_pki_secret_backend_config_acme.this'    pki_int/config/acme
tofu import 'module.vault_pki_int.vault_pki_secret_backend_role.intermediate'   pki_int/roles/intermediate

# ── internal intermediate (pki_int_internal) ──
tofu import 'module.vault_pki_int_internal.vault_mount.pki_int_internal' pki_int_internal
tofu import 'module.vault_pki_int_internal.vault_pki_secret_backend_config_cluster.this' pki_int_internal/config/cluster
tofu import 'module.vault_pki_int_internal.vault_pki_secret_backend_config_urls.this'    pki_int_internal/config/urls
tofu import 'module.vault_pki_int_internal.vault_pki_secret_backend_role.intermediate'   pki_int_internal/roles/intermediate

# ── Connect CA (pki_int_connect) ──
# The connect-ca role is created on the approle mount imported above (no clash —
# this module only references that mount by path). The KV stash imports by its
# data path (mount/data/name). After adopting these, follow "Consul Connect CA
# cutover" below to switch the live cluster onto the Vault provider.
tofu import 'module.vault_pki_int_connect.vault_mount.pki_int_connect'                    pki_int_connect
tofu import 'module.vault_pki_int_connect.vault_policy.connect_ca'                        consul-connect-ca
tofu import 'module.vault_pki_int_connect.vault_approle_auth_backend_role.connect_ca'     auth/approle/role/consul-connect-ca
tofu import 'module.vault_pki_int_connect.vault_kv_secret_v2.role_id'                     kv/data/consul/connect-ca

# ── SSH client-cert CA (ssh-client-signer) ──
tofu import 'module.vault_ssh.vault_mount.ssh' ssh-client-signer
tofu import 'module.vault_ssh.vault_ssh_secret_backend_role.admin' ssh-client-signer/roles/admin
# The CA keypair (vault_ssh_secret_backend_ca) is bootstrap-gated and not
# imported — its private half isn't readable, so it's treated as cold-start-only
# like the PKI key material.

# ── OIDC auth method (oidc) ──
tofu import 'module.vault_oidc.vault_jwt_auth_backend.oidc'      oidc
tofu import 'module.vault_oidc.vault_jwt_auth_backend_role.role' auth/oidc/role/admin
# Vault never returns oidc_client_secret on read, so right after import the next
# plan shows the backend wanting to (re)write the secret from your TF_VAR — that's
# expected and harmless, it just re-asserts the value you already supplied.

# ── AppRole auth (vault-agent) ──
tofu import 'module.vault_approle.vault_auth_backend.approle' approle
tofu import 'module.vault_approle.vault_approle_auth_backend_role.this' auth/approle/role/vault-agent
# internal-server-certs is module-owned (policies/internal-server-certs.hcl):
tofu import 'module.vault_approle.vault_policy.owned["internal-server-certs.hcl"]' internal-server-certs
# Verify tofu adopted the existing role rather than a new one:
#   tofu output vault_approle_role_id   # must equal os/etc/vault-agent.d/agent.roleid
# The module is pinned to the live role (token_type=batch, token_ttl=20m,
# token_bound_cidrs, token_policies=[internal-server-certs] via owned_policy_files),
# so plan should be a no-op. If it shows a token_policies change, add the extra
# policies to the module call before applying — dropping one breaks cert rendering.

# ── Nomad secrets engine (nomad) ── needs NOMAD_TOKEN = a management token
# The vault provider keys this backend's existence on nomad/config/lease. If your
# engine was set up without it, import reports "non-existent" — create it first:
#   vault write nomad/config/lease ttl=0 max_ttl=0
# (the module then takes ownership and reconciles it to its configured TTLs).
tofu import 'module.vault_nomad.vault_nomad_secret_backend.nomad' nomad
tofu import 'module.vault_nomad.vault_nomad_secret_role.mgmt'     nomad/role/mgmt
# The dedicated engine token — import the existing one by accessor (get it from
# `nomad acl token list`), which reads its secret_id back cleanly:
#   tofu import 'module.vault_nomad.nomad_acl_token.engine' <accessor-id>
# Alternatively, skip the import and just apply: tofu mints a fresh dedicated
# token (safe rotation — re-applying is idempotent) and updates nomad/config/access
# to it; delete the now-orphaned old token by hand.

# ── Nomad workload identity into Vault (vault_nomad_wi) ──
# Adopt the live method + roles + policy — do NOT apply blind: the nomad-workloads
# policy embeds the mount accessor, and import preserves the existing accessor, so
# a fresh apply would enable a new mount with a new accessor and orphan the
# templating. Both the nomad-workloads (rendered from the accessor) and
# raft-snapshots (policies/raft-snapshots.hcl) policies are module-owned —
# imported here, not in the root policy loop below. Confirm the live config first:
#   vault read auth/jwt-nomad/config
#   vault read auth/jwt-nomad/role/nomad-workloads
#   vault read auth/jwt-nomad/role/raft-snapshotter
tofu import 'module.vault_nomad_wi.vault_jwt_auth_backend.nomad_workloads'               jwt-nomad
tofu import 'module.vault_nomad_wi.vault_jwt_auth_backend_role.this["nomad-workloads"]'  auth/jwt-nomad/role/nomad-workloads
tofu import 'module.vault_nomad_wi.vault_jwt_auth_backend_role.this["raft-snapshotter"]' auth/jwt-nomad/role/raft-snapshotter
tofu import 'module.vault_nomad_wi.vault_policy.nomad_workloads'                          nomad-workloads
tofu import 'module.vault_nomad_wi.vault_policy.owned["raft-snapshots.hcl"]'              raft-snapshots

# ── Nomad OIDC login (pocket-id) ── also needs a management token
tofu import 'module.nomad_oidc.nomad_acl_auth_method.pocket_id' pocket-id
# Binding rule imports by its UUID (from `nomad acl binding-rule list`):
#   tofu import 'module.nomad_oidc.nomad_acl_binding_rule.admin' <rule-id>

# ── Root ACL policies ── only `admin` is at the root; module-owned
# policies are imported in their module's block (vault_nomad_wi, vault_approle,
# consul_acl, consul_nomad_wi). Import ID is the policy name:
tofu import 'vault_policy.this["admin.hcl"]' admin
tofu import 'nomad_acl_policy.this["admin.hcl"]' admin
# There's no root-level Consul policy list — Consul admin is the built-in
# global-management; every other Consul policy is module-owned and imported in
# its module's block.

# ── Vault Consul secrets engine (consul) ── needs CONSUL_HTTP_TOKEN = mgmt token
tofu import 'module.vault_consul.vault_consul_secret_backend.consul'      consul
tofu import 'module.vault_consul.vault_consul_secret_backend_role.mgmt'   consul/roles/mgmt
# The dedicated engine token — import the existing one by accessor (from
# `consul acl token list`), which reads its secret_id back via the data source:
#   tofu import 'module.vault_consul.consul_acl_token.engine' <accessor-id>
# Or skip the import and apply: tofu mints a fresh dedicated token (safe rotation)
# and repoints consul/config/access at it; delete the orphaned old token by hand.

# ── Consul ACL base (consul_acl) ──
# The module owns its baseline policies — import ID is the policy *ID* (UUID):
for p in anonymous consul-agent consul-config-services nomad-agent vault-registration; do
  tofu import "module.consul_acl.consul_acl_policy.owned[\"$p.hcl\"]" \
    "$(consul acl policy read -name "$p" -format json | jq -r .ID)"
done
# The anonymous attachment imports as "<token-id>:<policy-id>":
tofu import 'module.consul_acl.consul_acl_token_policy_attachment.anonymous' \
  "00000000-0000-0000-0000-000000000002:$(consul acl policy read -name anonymous -format json | jq -r .ID)"
# Daemon tokens by accessor (from `consul acl token list`); their secret_id data
# sources and KV writes reconcile on the next apply:
#   tofu import 'module.consul_acl.consul_acl_token.daemon["consul-agent"]'           <accessor-id>
#   tofu import 'module.consul_acl.consul_acl_token.daemon["consul-config-services"]' <accessor-id>
#   tofu import 'module.consul_acl.consul_acl_token.daemon["nomad-agent"]'            <accessor-id>
#   tofu import 'module.consul_acl.consul_acl_token.daemon["vault-registration"]'     <accessor-id>

# ── Consul Nomad workload identity (consul_nomad_wi) ──
tofu import 'module.consul_nomad_wi.consul_acl_auth_method.nomad_workloads' nomad-workloads
# The module owns its workload policies — import ID is the policy *ID* (UUID):
for p in nomad-tasks traefik traefik-ingress prometheus; do
  tofu import "module.consul_nomad_wi.consul_acl_policy.owned[\"$p.hcl\"]" \
    "$(consul acl policy read -name "$p" -format json | jq -r .ID)"
done
tofu import 'module.consul_nomad_wi.consul_acl_role.nomad_tasks' \
  "$(consul acl role read -name nomad-tasks -format json | jq -r .ID)"
# The task-identity roles carry the like-named policy (import by role UUID):
#   tofu import 'module.consul_nomad_wi.consul_acl_role.task_identity["traefik"]' <role-id>
# Binding rules import by their UUID (from `consul acl binding-rule list -method nomad-workloads`):
#   tofu import 'module.consul_nomad_wi.consul_acl_binding_rule.service' <rule-id>
#   tofu import 'module.consul_nomad_wi.consul_acl_binding_rule.tasks'   <rule-id>

# ── Consul mesh config entries (consul_mesh) ──
# proxy-defaults/global is created by tofu (nothing to import). The service
# intentions were applied out of band, so import each by its destination name
# (the map keys in modules/consul/mesh/intentions.tf — mirror them here):
for d in '*' deluge deluge-inbound go2rtc homeassistant jackett mosquitto \
         nut pocket-id postgres prometheus victorialogs zwave-ws; do
  tofu import "module.consul_mesh.consul_config_entry_service_intentions.this[\"$d\"]" "$d"
done
```

If nothing was created out of band (ACLs freshly bootstrapped), skip the Consul
imports and just `tofu apply` — tofu mints the engine + daemon tokens and writes
KV. Vault never returns a KV value on the first read after import, so a
`vault_kv_secret_v2` may show a re-write on the plan right after import; that's
expected and just re-asserts the token.

The key-generating resources (root `root_cert`; intermediate
`intermediate_cert_request` / `root_sign_intermediate` / `intermediate_set_signed`)
model a one-shot _action_, not readable state — they have nothing to import,
which is why they're gated behind `bootstrap` and simply absent from an
existing-cluster plan. That "generation is an action, not state" seam is exactly
the awkward-to-declarative part; the mount/role/config resources are the clean
win.

## Resources by module

What each module manages. Resources marked _bootstrap_ only exist when
`bootstrap = true`.

### modules/vault/pki

- `vault_mount.pki` — the mount (10y max-lease-ttl)
- `vault_pki_secret_backend_root_cert` — self-signed root (_bootstrap_)
- `vault_pki_secret_backend_config_cluster` / `..._config_urls` — AIA/cluster config
- `vault_pki_secret_backend_role` — the `servers` role

### modules/vault/pki_int

- `vault_mount.pki_int` — the mount, with ACME `passthrough_request_headers` / `allowed_response_headers`
- `vault_pki_secret_backend_intermediate_cert_request` → `vault_pki_secret_backend_root_sign_intermediate` → `vault_pki_secret_backend_intermediate_set_signed` — the sign chain (_bootstrap_)
- `vault_pki_secret_backend_config_cluster` / `..._config_urls` / `..._config_acme`
- `vault_pki_secret_backend_role` — the `intermediate` role

### modules/vault/pki_int_internal

- `vault_mount.pki_int_internal` — the mount (no ACME)
- the same three-resource sign chain (_bootstrap_)
- `vault_pki_secret_backend_config_cluster` / `..._config_urls`
- `vault_pki_secret_backend_role` — the `intermediate` role, `no_store=true`

### modules/vault/ssh

- `vault_mount.ssh` — the `ssh-client-signer` mount
- `vault_ssh_secret_backend_ca` — the CA signing keypair (_bootstrap_)
- `vault_ssh_secret_backend_role` — the `admin` `key_type=ca` role

### modules/vault/oidc

- `vault_jwt_auth_backend` — the `oidc` method (`type = "oidc"`, discovery + client creds + `default_role`)
- `vault_jwt_auth_backend_role` — the `admin` role (`role_type = "oidc"`)

### modules/vault/approle

- `vault_auth_backend` — the `approle` auth method
- `vault_approle_auth_backend_role` — the `vault-agent` role (role_id-only, batch tokens)
- `vault_policy.owned` (`for_each`) — one per `policies/*.hcl` in this module (`internal-server-certs`, attached to the role via `owned_policy_files`)

### modules/vault/nomad

- `nomad_acl_token` — the dedicated management token the engine uses (lifecycle-owned)
- `vault_nomad_secret_backend` — the `nomad` mount + `config/access`
- `vault_nomad_secret_role` — the `mgmt` management/global role

### modules/vault/nomad-wi

- `vault_jwt_auth_backend` — the `jwt-nomad` JWT auth method (node-local Nomad JWKS, no embedded CA, `default_role`, `jwt_supported_algs = ["RS256"]`)
- `vault_jwt_auth_backend_role` (`for_each`) — the `nomad-workloads` and `raft-snapshotter` roles (periodic `service` tokens)
- `vault_policy.nomad_workloads` — the accessor-templated per-workload KV policy (rendered from `templates/nomad-workloads.hcl.tftpl`)
- `vault_policy.owned` (`for_each`) — one per `policies/*.hcl` in this module (`raft-snapshots`, attached to the `raft-snapshotter` role via `owned_policies`); other policies come from `policies.tf`

### modules/nomad/oidc

- `nomad_acl_auth_method` — the `pocket-id` OIDC method
- `nomad_acl_binding_rule` — pocket-id → `admin` policy

### modules/vault/consul

- `consul_acl_token` — the dedicated Consul management token the engine uses (a
  client token carrying `global-management`; lifecycle-owned, like the Nomad one)
- `consul_acl_token_secret_id` (data) — reads that token's SecretID for `config/access`
- `vault_consul_secret_backend` — the `consul` mount + `config/access`
- `vault_consul_secret_backend_role` — the `mgmt` role (`global-management`)

### modules/consul/acl

- `consul_acl_policy.owned` (`for_each`) — one per `policies/*.hcl` in this module (`anonymous` + the four daemon policies)
- `consul_acl_token_policy_attachment` — the `anonymous` policy on the built-in anonymous token
- `consul_acl_token.daemon` — the four non-expiring daemon tokens (`for_each`)
- `consul_acl_token_secret_id.daemon` (data) — reads each daemon token's SecretID
- `vault_kv_secret_v2.daemon` — each token stashed at `kv/consul/tokens/<name>` (`for_each`)

### modules/consul/nomad-wi

- `consul_acl_policy.owned` (`for_each`) — one per `policies/*.hcl` in this module (`nomad-tasks` + the task-identity policies `traefik`, `traefik-ingress`, `prometheus`)
- `consul_acl_auth_method` — the `nomad-workloads` JWT method
- `consul_acl_role.nomad_tasks` — the `nomad-tasks` role (carries the owned `nomad-tasks` policy)
- `consul_acl_role.task_identity` (`for_each`) — extra per-task-identity roles (each carries its owned `policy_file`)
- `consul_acl_binding_rule.service` / `.tasks` / `.task_identity` — per-service identity / serviceless → role / additive task-identity rules

### policies.tf (root)

Cross-cutting / human-facing policies only; a policy attached by a single module
(as its implementation detail) is owned by that module instead — see the
`modules/vault/{nomad-wi,approle}` and `modules/consul/{acl,nomad-wi}` sections.

- `vault_policy.this` — one per `policies/vault/*.hcl` (`for_each`; just `admin`)
- `nomad_acl_policy.this` — one per `policies/nomad/*.hcl` (`for_each`; `admin`)

(No `consul_acl_policy.this` — Consul has no root policy list; its admin is the built-in `global-management` and every other Consul policy is module-owned.)
