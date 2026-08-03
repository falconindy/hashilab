# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repo manages a homelab built on the HashiCorp stack: **Consul** (service mesh + DNS + KV), **Nomad** (workload orchestration), and **Vault** (PKI + secrets). Ansible configures the underlying OS and deploys the daemons; Nomad HCL job files define the actual workloads.

Cluster topology: three servers (`nomad0-2.node.home`) running in `dc1` act as Consul/Nomad/Vault servers and clients, plus a bastion node in `dc2`. All inter-service communication uses Consul Connect (Envoy sidecar proxies with mTLS).

## Formatting and pre-commit

Pre-commit hooks run on every commit (see `.pre-commit-config.yaml`):

- `nomad fmt` — formats all `jobs/*.hcl` files
- `tofu fmt` — formats the OpenTofu config under `tofu/`
- `ruff format` — formats Python scripts in `bin/`
- `prettier` — formats everything else (JS, HTML, JSON, YAML, Markdown)
- `ansible-lint` — lints Ansible playbooks and roles

Run them manually:

```bash
pre-commit run --all-files        # run all hooks
nomad fmt jobs/<file>.hcl         # format a single job
tofu fmt -recursive tofu          # format the tofu config
ruff format bin/<script>.py       # format a single script
```

## Deploying jobs

```bash
nomad job run jobs/<name>.hcl     # deploy or update a job
nomad job status <name>           # check job status
nomad job stop <name>             # stop a job
```

## Ansible

Ansible connects as `root` (`remote_user` in `ansible.cfg`) using a Vault-signed
SSH certificate, not a static key. Load one into your ssh-agent first:

```bash
vault login -method=oidc      # passkey
bin/vault-ssh-agent           # signs a root cert, loads it into the agent
```

Then run as usual:

```bash
ansible-playbook site.yml -i inventory/hosts.yml                    # full run
ansible-playbook site.yml -i inventory/hosts.yml --tags consul      # single role
ansible-playbook site.yml -i inventory/hosts.yml -l nomad0.node.home  # single host
```

Available tags match role names: `trust`, `base`, `systemd`, `keepalived`, `consul`, `nomad`, `vault`, `vault_agent`, `synology`. The `trust` role (home Root CA + Vault SSH client CA) is OS-agnostic and runs on every host; `base` (apt packages, editor, clusterdata NFS mount) is gated to Debian hosts so non-Debian nodes can take `trust` without it.

The Synology NAS (`nasty.node.home`) is not Debian, so `site.yml` splits into two plays: `Deploy All` (`hosts: all:!synology`) for the Debian fleet, and `Deploy Synology` (`hosts: synology`) running the thin `synology` role — which manages the NAS's Consul client `consul.hcl` plus its `home-ca.pem` trust anchor (via `synopkg restart` on change). nasty is a bare `auto_encrypt` client: it serves no HTTP/gRPC and the servers issue and rotate its RPC cert, so the only TLS material delivered to it is the static home Root CA — there's no per-node cert to provision. The Consul package itself stays managed out of band. Connection identity for the NAS lives in `inventory/group_vars/synology.yml` (SSH as `nasty` + sudo, since DSM forbids root SSH).

## Architecture

### Service discovery and DNS

Consul runs as a server cluster on `nomad0-2` and as a client on all nodes. The `.service.home` and `.consul.` DNS zones are served by **CoreDNS** (running as a Nomad `system` job), which forwards those zones to Consul DNS on port 8600 and all other queries to AdGuard (falling back to `1.1.1.1`/`8.8.8.8`). `systemd-resolved` is configured to use `172.17.0.1` (the Docker bridge) as its upstream.

### Ingress

**Traefik** (two instances, `dc1`) reads the Consul catalog for services tagged `traefik.enable=true` and routes `<service-name>.service.home` to them. TLS is issued via Vault's ACME endpoint (`pki_int`) using the HTTP challenge. The `internal-only` middleware restricts access to RFC1918 ranges.

To expose a new service through Traefik, add `"traefik.enable=true"` to its `service.tags`. To override the hostname slug, add `"traefik.http.routers.<name>.rule=Host(...)"`.

To show a service in the homelab dashboard, also add `"homelabdash.uri=<path>"` (optional) or `"homelabdash.slug=<name>"` (to override the display name). Add `"homelabdash.hide"` to suppress it entirely.

### PKI / TLS

Vault runs four PKI secret engines:

- `pki` — self-signed root CA (`home`, 10-year TTL)
- `pki_int` — intermediate CA with ACME enabled; used by Traefik to issue TLS certs for `*.service.home`
- `pki_int_internal` — intermediate CA for internal client certs (no ACME, no storage)
- `pki_int_connect` — intermediate CA for the Consul Connect mesh CA. Unlike the others, **Consul** (not tofu) generates the intermediate, has `pki` sign it, and rotates every mesh leaf cert; tofu (`modules/vault/pki_int_connect`) only reserves the mount and grants the Consul servers a keyless AppRole (`consul-connect-ca`, role_id in Vault KV `kv/consul/connect-ca`) scoped by the `consul-connect-ca` policy. Consul's server config points at it via `connect { ca_provider = "vault" }` in `server.hcl`

All nodes run **vault-agent** (AppRole auth, role ID in `/etc/vault-agent.d/agent.roleid`) which renders TLS certs for Nomad, Consul, and Vault itself from templates in `/etc/vault-agent.d/*.tpl`. The CA bundle is at `/etc/ssl/certs/home.pem` on every node.

Vault also runs an **SSH client CA** on the `ssh-client-signer` mount. The `trust` role trusts its public key on every host (`/etc/ssh/trusted-user-ca-keys.pem` via a `sshd_config.d` drop-in), so `vault login -method=oidc` followed by `bin/vault-ssh-agent` to load a short-lived, pocket-id-gated certificate — no static keys in `authorized_keys`.

### Control-plane provisioning (OpenTofu)

The Vault, Nomad and Consul control plane — the three PKI engines above, the SSH client CA, OIDC login for both Vault and Nomad, the Vault→Nomad and Vault→Consul secrets engines, and the **Consul ACL layer** — is provisioned declaratively by the OpenTofu config in `tofu/` (one module per engine under `modules/<provider>/`). The Consul ACL layer covers: the Vault Consul secrets engine (`modules/vault/consul`, break-glass management tokens via `bin/supercow`); the baseline ACL identities (`modules/consul/acl` — the `anonymous`-token policy attachment plus the four non-expiring daemon tokens `consul-agent`/`consul-config-services`/`nomad-agent`/`vault-registration`, each stashed in Vault KV `kv/consul/tokens/*` for the Ansible roles); and the Nomad workload-identity flow (`modules/consul/nomad-wi` — the `nomad-workloads` JWT auth method, its binding rules, and the `nomad-tasks` role). Key-generating steps (root/intermediate CAs, the SSH CA) sit behind a `bootstrap` variable, default false, so routine plans can't regenerate a live CA; an already-running cluster is adopted with `tofu import` rather than a fresh apply. State can contain secrets (the Vault-Nomad and Vault-Consul engine management tokens, the Consul daemon tokens), so it must be kept off the repo (encrypted/remote backend). Vault, Nomad and Consul ACL **policies** are also managed here: cross-cutting/human-facing ones via `tofu/policies.tf` (one resource per `tofu/policies/{vault,nomad}/*.hcl` file — currently just `admin` on Vault and Nomad), while a policy attached by a single module — as an implementation detail of it — lives in that module's `policies/` dir and is owned by it (`raft-snapshots` in `modules/vault/nomad-wi`, `internal-server-certs` in `modules/vault/approle`, the `anonymous`/daemon policies in `modules/consul/acl`, the workload policies `nomad-tasks`/`traefik`/`traefik-ingress`/`prometheus` in `modules/consul/nomad-wi`). There's no root-level Consul policy list: Consul's admin is the built-in `global-management` (delivered via `bin/supercow`), and every other Consul policy is module-owned. The Consul-provider modules need a Consul **management** token in `CONSUL_HTTP_TOKEN`. See `tofu/README.md` for per-module import commands and the auth/env setup.

### Nomad jobs

Jobs live in `jobs/`. Key patterns:

- **Template delimiters**: Jobs that embed Go-template-style config (e.g., Consul template syntax) use `left_delimiter = "[["` and `right_delimiter = "]]"` to avoid collisions with Nomad's own `{{ }}` template processing.
- **Consul Connect**: Most services use `connect { sidecar_service {} }` for mTLS. How a consumer reaches its dependencies follows one of three patterns, in preference order:
  - **Transparent proxy (default)**: add `proxy { transparent_proxy { no_dns = true } }` and a `dns { servers = ["172.17.0.1"] }` block on the group network, then address deps as `<dest-service>.virtual.home:80` — Envoy routes off the service's virtual IP, so the connect port is `80` regardless of the destination's registered port (e.g. `postgres.virtual.home:80`, not `:5432`). No upstream/port bookkeeping; the mesh intention is the only thing to add per dependency. TP's inbound redirect swallows the raw host-mapped Envoy metrics port, so the sidecar metrics must be surfaced through an `expose { path { path = "/metrics", local_path_port = 9102, listener_port = "envoy_metrics" } }` block, keeping the usual `port "envoy_metrics" { to = 9102 }` (Nomad auto-adds the expose `local_path_port` to `exclude_inbound_ports`, so the scrape bypasses the redirect).
  - **Explicit `upstreams`**: reserved for services that do their own LAN discovery or broadcast, where transparent proxy's netns iptables REDIRECT breaks direct-to-device traffic (e.g. `homeassistant`). Declared as `upstreams { destination_name = "..." local_bind_port = ... }` and accessed via `127.0.0.1:<port>`.
  - **Colocate + loopback (no mesh)**: for a private helper consumed by exactly one service, put it as a second task in the consumer's group and reach it over `127.0.0.1` — no service registration, no sidecar, no intention (e.g. `blackbox-exporter` inside the `prometheus` group).
- **Vault secrets**: Tasks that need Vault secrets include a bare `vault {}` block; Nomad injects a short-lived token and sets `VAULT_TOKEN`.
- **Persistent data**: Host-mounted at `/clusterdata/<service>` for data that must survive allocation restarts.
- **Envoy metrics**: Each sidecar exposes Prometheus metrics on a dynamic port; tasks set `meta { envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}" }` for Prometheus to scrape.

### Monitoring

Prometheus (in `jobs/monitoring.hcl`) scrapes all targets via Consul service discovery — no static targets. Grafana reads from Prometheus. The Blackbox Exporter probes TLS endpoints for certificate expiry on `vault` and `omada-controller` (the only services with no native metric). Consul agent cert expiry is scraped via `consul_agent_tls_cert_expiry` off each agent's `/v1/agent/metrics` — discovered through the `nomad-client` service, which every Nomad-running node registers. Nomad agent cert expiry comes from `nomad_agent_tls_cert_expiration_seconds` on the existing `/v1/metrics` scrape. `x509-exporter` watches client certs on each node.

### Dashboard

`www/homelabdash/` is a static single-page app that polls the Consul HTTP API using blocking queries (long-poll on `x-consul-index`) to watch the service catalog and health state in real time. A second "Infrastructure" tab polls Prometheus (`/api/v1/query`, timer-based like the alert banner) for server uptime (`node_boot_time_seconds`) and TLS certificate expiration by cert type — Consul (`consul_agent_tls_cert_expiry`), Nomad (`nomad_agent_tls_cert_expiration_seconds`), Vault server/client (`x509_cert_not_after` filtered by filepath) — plus the CA expiry of each PKI issuing mount (`pki`, `pki_int`, `pki_int_internal`, `pki_int_connect`, also from `x509_cert_not_after`; see `jobs/x509-exporter.hcl`). Deployed by running `bin/deploy-www`, which rsyncs to `/clusterdata/www/` (requires the mount to be present).

### Utility scripts

| Script                          | Purpose                                                                                                                                                                                                                                                                                                                       |
| ------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bin/cfctl`                     | Manage Cloudflare CNAME records tagged `#managed`; fetches API key + zone ID from Vault KV (`kv/cli/cfctl`)                                                                                                                                                                                                                   |
| `bin/vault-ssh-agent`           | Mint a Vault-signed cert and load it into ssh-agent so `ssh`/`ansible-playbook` authenticate with it (drives Ansible keylessly)                                                                                                                                                                                               |
| `bin/supercow`                  | Break-glass into a subshell holding **both** Consul and Nomad **management** tokens, minted from the Vault Consul/Nomad secrets engines (`{consul,nomad}/creds/mgmt`), renewed to a shared TTL, and revoked on exit. Needed for Consul/Nomad ACL administration and to seed `CONSUL_HTTP_TOKEN` for the `tofu` Consul modules |
| `bin/deploy-www`                | Rsync `www/` to `/clusterdata/www/`                                                                                                                                                                                                                                                                                           |
| `bin/deploy-grafana-dashboards` | Rsync `grafana/dashboards/*.json` to `/clusterdata/grafana/dashboards/`; Grafana file-provisions and hot-reloads them                                                                                                                                                                                                         |

### Renovate

`renovate.json` uses a custom regex manager to parse `image = "repo/name:tag"` lines in `jobs/*.hcl` and open PRs for updates. Major version bumps are disabled for `postgres` and `linuxserver/deluge`. LinuxServer images use a non-standard versioning scheme handled by the `versioning` regex rule.
