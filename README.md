# hashilab

A self-hosted homelab built on the **HashiCorp stack** — [Consul](https://www.consul.io/),
[Nomad](https://www.nomadproject.io/), and [Vault](https://www.vaultproject.io/) — where
everything is declarative, every wire is encrypted, and nothing is clicked into place by hand.

Three mini-PCs and a NAS run a fleet of containerized services behind a zero-trust service
mesh. The OS is configured by Ansible, the control plane is provisioned by OpenTofu, the
workloads are scheduled by Nomad, and dependency bumps arrive as Renovate PRs. Certificates
rotate themselves. SSH has no static keys. Secrets never touch the repo.

---

## The big picture

```
    LAN                                    outside world
     │                                          │
     │  *.service.home                          │  router port-forward ─► keepalived VIP
     ▼                                          ▼
 ┌─────────────────────────────┐   ┌─────────────────────────────┐
 │  traefik                    │   │  traefik-ingress            │
 │  <name>.service.home        │   │  <name>.falconindy.com      │
 │  ACME via Vault             │   │  ACME via Let's Encrypt     │
 └──────────────┬──────────────┘   └───────────────┬─────────────┘
                │                                  │
                │                                  │
                └───────────────┬──────────────────┘
                                │  routed via the Consul catalog
 ┌──────────────────────────────┴───────────────────────────────────────┐
 │                     Consul service mesh                              │
 │    mTLS everywhere · Envoy sidecars · default-deny intentions        │
 └──────┬───────────────────┬───────────────────┬────────────────┬──────┘
        │                   │                   │                │
   ┌────┴────┐         ┌────┴────┐         ┌────┴────┐      ┌────┴────┐
   │ nomad0  │         │ nomad1  │         │ nomad2  │      │ bastion │
   │ dc1     │         │ dc1     │         │ dc1     │      │ dc2     │
   └─────────┘         └─────────┘         └─────────┘      └─────────┘
       server + client for Consul / Nomad / Vault            client-only

   ┌──────────────────────── control plane ────────────────────────┐
   │  Consul  service discovery · DNS · KV · ACLs                  │
   │  Nomad   workload orchestration (Docker + system jobs)        │
   │  Vault   PKI (3 CAs) · SSH CA · OIDC · dynamic secrets        │
   └───────────────────────────────────────────────────────────────┘
```

**Topology.** Three servers (`nomad0-2.node.home`) in `dc1` each run Consul, Nomad,
and Vault as both server and client. A `bastion` node in `dc2` and a Synology NAS join
as clients.

**Two front doors, same services.** An internal **Traefik** pair routes
`<name>.service.home` for anything on the LAN, issuing certs from Vault's ACME endpoint.
A separate **`traefik-ingress`** instance handles traffic from the outside world: the
router port-forwards to a **keepalived** VIP that floats across the servers, and the VIP
hands that traffic to `traefik-ingress`, which serves the same jobs under
`<name>.falconindy.com` with a Let's Encrypt wildcard cert (plus geoblocking). Both
Traefiks resolve their backends from the same Consul catalog — the two hostnames are
just different front-door names for one service running in the mesh.

**The mesh.** Every service talks to every other service through
[Consul Connect](https://developer.hashicorp.com/consul/docs/connect) — Envoy sidecar
proxies doing mutual TLS. Intentions are default-deny, so nothing reaches anything it
wasn't explicitly allowed to.

**PKI, all the way down.** Vault runs a self-signed root CA plus two intermediates.
The internal Traefik issues `*.service.home` certs from Vault's **ACME** endpoint, while
the external `traefik-ingress` uses a Let's Encrypt wildcard for `*.falconindy.com`;
internal client certs come from a no-storage intermediate. `vault-agent` on every node
renders and rotates the Consul/Nomad/Vault daemon certs from templates — no cert is ever
copied by hand.

**Keyless SSH.** There are no keys in `authorized_keys`. You `vault login -method=oidc`
(a passkey, via [Pocket-ID](https://github.com/pocket-id/pocket-id)), mint a short-lived
certificate off Vault's SSH CA, and connect. Ansible drives the whole fleet the same way.

---

## What runs here

All of these are Nomad jobs under [`jobs/`](jobs/), scheduled across the cluster and
discovered through Consul. A few highlights:

| Domain                  | Services                                                                         |
| ----------------------- | -------------------------------------------------------------------------------- |
| **Ingress & DNS**       | Traefik (internal + external ingress), CoreDNS, AdGuard Home, Cloudflare DDNS    |
| **Identity & platform** | Pocket-ID (OIDC), Postgres, a private Docker registry                            |
| **Observability**       | Prometheus + Grafana, VictoriaLogs + Vector, node/x509/omada/blackbox exporters  |
| **Home & IoT**          | Home Assistant, ESPHome, Z-Wave JS, go2rtc, rtl_433, Mosquitto (MQTT), TeslaMate |
| **Media**               | Jellyfin, \*arr suite (Sonarr/Radarr/Jackett), Deluge                            |
| **Networking**          | Omada controller, Tailscale,                                                     |
| **Utilities**           | The Lounge (IRC), Stirling PDF                                                   |

**Discovery is automatic.** Tag a service `traefik.enable=true` and it's routed at
`<name>.service.home` with a fresh TLS cert. Prometheus scrapes every target straight
from the Consul catalog — there are no static target lists anywhere.

**A dashboard that follows along.** [`www/homelabdash/`](www/homelabdash/) is a static
SPA that long-polls the Consul HTTP API (blocking queries on `x-consul-index`) to show
the live service catalog and health, updating the instant anything changes.

---

## How it's maintained

The repo is the source of truth. Three tools keep the cluster matching it.

### Ansible — the machines

Configures the OS and installs/configures the Consul, Nomad, and Vault daemons,
plus supporting bits (keepalived, systemd units, the NFS `clusterdata` mount).
Roles map one-to-one to `--tags`.

```bash
vault login -method=oidc                          # passkey
bin/vault-ssh-agent                               # load a signed SSH cert
ansible-playbook site.yml -i inventory/hosts.yml  # converge the fleet
```

The Synology NAS isn't Debian, so it gets its own thin play that manages only its
Consul client config — everything else on the NAS stays out of band.

### OpenTofu — the control plane

Everything _inside_ Vault/Nomad/Consul that would otherwise be a pile of `vault write`
commands is declared in [`tofu/`](tofu/), one module per engine: the three PKI CAs, the
SSH CA, OIDC login, the Vault→Nomad and Vault→Consul dynamic-secrets engines, and the
full Consul ACL layer (daemon tokens, the Nomad workload-identity flow, policies).

CA-generating steps sit behind a `bootstrap` flag so a routine `plan` can never
regenerate a live CA — a running cluster is _adopted_ with `tofu import`, not rebuilt.
State lives in Consul, never in the repo. See
[`tofu/README.md`](tofu/README.md) for per-module setup.

### Renovate — the dependencies

A custom regex manager parses `image = "repo/name:tag"` lines in `jobs/*.hcl` and opens
a PR for every upstream release. Major bumps are pinned for the touchy ones (Postgres,
Deluge). Merge the PR, `nomad job run` the job, done.

---

## Repo layout

```
jobs/         Nomad job specs — the actual workloads
roles/        Ansible roles (trust, base, consul, nomad, vault, vault_agent, …)
site.yml      top-level playbook; inventory/ has hosts + group_vars
tofu/         OpenTofu control-plane config (modules/<provider>/<engine>)
bin/          operator tooling — see below
www/          homelabdash static SPA
grafana/      provisioned dashboards
RUNBOOK.md    break-glass procedures (root-token ceremony, etc.)
CLAUDE.md     detailed architecture notes
```

### Operator tooling (`bin/`)

| Script                                     | Purpose                                                                                    |
| ------------------------------------------ | ------------------------------------------------------------------------------------------ |
| `vault-ssh` / `vault-ssh-agent`            | Mint a short-lived SSH cert off the Vault CA and connect (or feed ssh-agent for Ansible)   |
| `supercow`                                 | Break-glass subshell holding fresh Consul **and** Nomad management tokens, revoked on exit |
| `certctl.py`                               | Certificate lifecycle tooling for anything vault/vault-agent can't manage                  |
| `cfctl`                                    | Manage `#managed` Cloudflare CNAMEs from Vault-stored credentials                          |
| `deploy-www` / `deploy-grafana-dashboards` | Rsync the SPA / dashboards to `clusterdata`                                                |
| `registryctl`                              | Manage the private Docker registry                                                         |

---

## Design principles

- **Declarative or it didn't happen.** Ansible + OpenTofu + Nomad specs define the whole
  system; there's a runbook for the rare manual ceremony, and that's it.
- **Zero-trust by default.** mTLS on every hop, default-deny intentions, ACLs that
  fail closed, no long-lived credentials.
- **Nothing static that can be short-lived.** SSH certs, TLS certs, and secrets are all
  minted on demand and rotated automatically.
- **Secrets stay out of git.** Tofu state is remote and encrypted; tokens live in Vault
  KV, not in files.

See [`CLAUDE.md`](CLAUDE.md) for the deep architecture dive and [`RUNBOOK.md`](RUNBOOK.md)
for what to do when it's on fire.
