# tofu/ — declarative Vault + Nomad control plane

OpenTofu configuration that manages the Vault and Nomad control plane
declaratively: the PKI engines, the SSH client CA, OIDC login for both Vault and
Nomad, and the Vault→Nomad secrets-engine integration. State tracking gives
idempotence and drift detection; the key-generating steps are fenced behind a
`bootstrap` flag so day-to-day runs can't regenerate a live CA.

Modules are grouped by provider under `modules/<provider>/` and the block labels
carry the same namespace (`module.vault_pki`, `module.vault_ssh`, …) so
Nomad-side modules don't collide with Vault ones. It's a real collision, not
hypothetical: the Vault Nomad _secrets engine_ is `modules/vault/nomad`, while
Nomad's own OIDC login is `modules/nomad/oidc` — without the namespace both would
just be "nomad".

## Modules

Three PKI engines:

- `modules/vault/pki` — the self-signed root CA (`home`, 10y): the `pki` mount,
  the self-signed root, `config/cluster`, `config/urls`, and the `servers` role.
- `modules/vault/pki_int` — the ACME intermediate: the `pki_int` mount (+ ACME
  header tuning), the CSR → root-sign → import chain, `config/cluster`,
  `config/urls`, the `intermediate` role, and `config/acme`.
- `modules/vault/pki_int_internal` — the internal-client-cert intermediate: same
  shape as `pki_int` but no ACME, and its `intermediate` role sets
  `no_store=true` with a longer `max_ttl` (4380h).

The root config (`main.tf`) wires them together: both intermediates' signing
`root_issuer_ref` is fed from `module.vault_pki.issuer_name`, so the chain is
explicit.

The SSH client-cert CA:

- `modules/vault/ssh` — the `ssh-client-signer` mount, the CA signing keypair, and
  the `admin` signing role. (The `ssh` Vault policy is managed centrally — see
  **Policies** below.)

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

Nomad OIDC login:

- `modules/nomad/oidc` — the `pocket-id` OIDC auth method + the binding rule that
  maps everyone authenticating through it to the `admin` policy. Nomad-provider
  only; like the Vault OIDC module it's pure config with **no bootstrap gate**.
  Uses a **separate** Pocket-ID client from Vault (the "Nomad" client — different
  id/secret). The `admin` policy the rule binds to is managed centrally (see
  **Policies**). Applying it needs a Nomad **management** token (auth-method +
  binding-rule creation is ACL administration).

Policies:

- `policies.tf` (root) — reconciles Vault ACL policies from `vault/policies/*.hcl`
  and Nomad ACL policies from `nomad/policies/*.hcl`, one resource per file via
  `for_each`. The policy name is the filename minus `.hcl`; add or remove a file
  to add or remove the policy. tofu only deletes policies backed by a file here
  and never touches built-ins (`default`/`root`, Nomad `anonymous`).

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

# ── SSH client-cert CA (ssh-client-signer) ──
tofu import 'module.vault_ssh.vault_mount.ssh' ssh-client-signer
tofu import 'module.vault_ssh.vault_ssh_secret_backend_role.admin' ssh-client-signer/roles/admin
# The CA keypair (vault_ssh_secret_backend_ca) is bootstrap-gated and not
# imported — its private half isn't readable, so it's treated as cold-start-only
# like the PKI key material. (The `ssh` policy is imported below with the rest.)

# ── OIDC auth method (oidc) ──
tofu import 'module.vault_oidc.vault_jwt_auth_backend.oidc'      oidc
tofu import 'module.vault_oidc.vault_jwt_auth_backend_role.role' auth/oidc/role/admin
# Vault never returns oidc_client_secret on read, so right after import the next
# plan shows the backend wanting to (re)write the secret from your TF_VAR — that's
# expected and harmless, it just re-asserts the value you already supplied.

# ── AppRole auth (vault-agent) ──
tofu import 'module.vault_approle.vault_auth_backend.approle' approle
tofu import 'module.vault_approle.vault_approle_auth_backend_role.this' auth/approle/role/vault-agent
# Verify tofu adopted the existing role rather than a new one:
#   tofu output vault_approle_role_id   # must equal os/etc/vault-agent.d/agent.roleid
# The module is pinned to the live role (token_type=batch, token_ttl=20m,
# secret_id_bound_cidrs, token_policies=[internal-server-certs]), so plan should
# be a no-op. If it shows a token_policies change, add the extra policies to the
# module call before applying — dropping one breaks cert rendering.

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

# ── Nomad OIDC login (pocket-id) ── also needs a management token
tofu import 'module.nomad_oidc.nomad_acl_auth_method.pocket_id' pocket-id
# Binding rule imports by its UUID (from `nomad acl binding-rule list`):
#   tofu import 'module.nomad_oidc.nomad_acl_binding_rule.admin' <rule-id>

# ── ACL policies ── keyed on filename; import ID is the policy name
for p in admin internal-server-certs nomad-user-policy nomad-workloads \
         prometheus-metrics raft-snapshots ssh; do
  tofu import "vault_policy.this[\"$p.hcl\"]" "$p"
done
tofu import 'nomad_acl_policy.this["admin.hcl"]' admin
```

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

### modules/vault/nomad

- `nomad_acl_token` — the dedicated management token the engine uses (lifecycle-owned)
- `vault_nomad_secret_backend` — the `nomad` mount + `config/access`
- `vault_nomad_secret_role` — the `mgmt` management/global role

### modules/nomad/oidc

- `nomad_acl_auth_method` — the `pocket-id` OIDC method
- `nomad_acl_binding_rule` — pocket-id → `admin` policy

### policies.tf (root)

- `vault_policy.this` — one per `vault/policies/*.hcl` (`for_each`)
- `nomad_acl_policy.this` — one per `nomad/policies/*.hcl` (`for_each`)
