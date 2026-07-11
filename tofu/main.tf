variable "root_issuer_name" {
  description = "issuer_name of the root CA, conventionally root-YYYY; feeds both the root and the intermediate's signing issuer_ref."
  type        = string
  default     = "root-2026"
}

variable "bootstrap" {
  description = <<-EOT
    Green-field cold start: generate the root, then generate + sign + import the
    intermediate. Leave false for an existing cluster (import the mounts/roles/
    config instead — see README). Applies to the PKI/SSH modules (the OIDC module
    has no key material, so it's always managed).
  EOT
  type        = bool
  default     = false
}

variable "home_ca_file" {
  description = "Path to the home CA PEM the nomad-workloads auth method embeds so Consul can validate Nomad's HTTPS JWKS endpoint. Read at plan time on the machine running tofu; present at this path on every node."
  type        = string
  default     = "/etc/ssl/certs/home.pem"
}

variable "vault_oidc_client_id" {
  description = "Pocket-ID \"Vault\" client ID. Supply in secrets.auto.tfvars (or TF_VAR_vault_oidc_client_id)."
  type        = string
}

variable "vault_oidc_client_secret" {
  description = "Pocket-ID \"Vault\" client secret. Supply in secrets.auto.tfvars (gitignored)."
  type        = string
  sensitive   = true
}

variable "nomad_oidc_client_id" {
  description = "Pocket-ID \"Nomad\" client ID (a DIFFERENT client from Vault's). Supply in secrets.auto.tfvars."
  type        = string
}

variable "nomad_oidc_client_secret" {
  description = "Pocket-ID \"Nomad\" client secret. Supply in secrets.auto.tfvars (gitignored)."
  type        = string
  sensitive   = true
}

module "vault_pki" {
  source = "./modules/vault/pki"

  # Root has no ACME; its cluster path only backs OCSP. Keep it on the plaintext,
  # node-local endpoint (AIA/CRL/OCSP over http, loop-free).
  cluster_base = local.vault_plaintext_base
  backend      = "pki"
  common_name  = "home"
  issuer_name  = var.root_issuer_name
  bootstrap    = var.bootstrap
}

module "vault_pki_int" {
  source = "./modules/vault/pki_int"

  # ACME mount: the cluster path is the ACME directory Traefik talks to, so it
  # must be the https/DNS endpoint. aia_base defaults to cluster_base, so the
  # *.service.home leaf certs carry https/DNS AIA (current behavior). Set
  # aia_base = local.vault_plaintext_base if you'd rather their AIA/CRL be
  # loop-free http — at the cost of off-node CRL fetches not resolving.
  cluster_base = local.vault_address
  backend      = "pki_int"
  common_name  = "home Vault Intermediate Authority"
  root_backend = module.vault_pki.backend
  # Chain the intermediate's signing issuer to the root the pki module owns.
  root_issuer_ref = module.vault_pki.issuer_name
  acme_enabled    = true
  bootstrap       = var.bootstrap
}

module "vault_pki_int_internal" {
  source = "./modules/vault/pki_int_internal"

  # No ACME; cluster path only backs OCSP. Plaintext node-local, like the root.
  cluster_base    = local.vault_plaintext_base
  backend         = "pki_int_internal"
  common_name     = "home Vault Intermediate Authority [Internal]"
  root_backend    = module.vault_pki.backend
  root_issuer_ref = module.vault_pki.issuer_name
  bootstrap       = var.bootstrap
}

# The Vault side of Consul Connect's mesh CA: the pki_int_connect intermediate
# mount, the least-privilege provider policy, and a keyless AppRole role the
# Consul servers log in with (role_id stashed in Vault KV for the consul role).
# Consul itself generates + rotates the intermediate and all leaf certs; the
# root (module.vault_pki) only signs the intermediate. The Consul-side provider
# switch is applied out of band with `consul connect ca set-config` — see
# README / RUNBOOK.
module "vault_pki_int_connect" {
  source = "./modules/vault/pki_int_connect"

  backend         = "pki_int_connect"
  approle_backend = "approle" # the mount module.vault_approle enables
  server_cidrs    = ["10.0.100.0/24"]
}

module "vault_ssh" {
  source = "./modules/vault/ssh"

  backend       = "ssh-client-signer"
  role_name     = "admin"
  allowed_users = "root"
  default_user  = "root"
  bootstrap     = var.bootstrap
}

module "vault_oidc" {
  source = "./modules/vault/oidc"

  vault_address      = local.vault_address
  path               = "oidc"
  oidc_discovery_url = local.oidc_discovery_url
  oidc_client_id     = var.vault_oidc_client_id
  oidc_client_secret = var.vault_oidc_client_secret
  role_name          = "admin"
  token_policies     = ["admin"]
}

module "vault_approle" {
  source = "./modules/vault/approle"

  backend            = "approle"
  role_name          = "vault-agent"
  owned_policy_files = ["internal-server-certs.hcl"]
  bind_secret_id     = false
  token_type         = "batch"
  token_ttl_seconds  = 1200 # 20m
  token_bound_cidrs  = ["10.0.100.0/24", "10.0.1.99/32"]
  # token_max_ttl (0) and secret_id_bound_cidrs ([]) match provider defaults, so
  # they're left null/unset.
}

module "vault_nomad" {
  source = "./modules/vault/nomad"

  backend           = "nomad"
  nomad_address     = local.nomad_address
  engine_token_name = "vault-nomad-secrets-engine"
  role_name         = "mgmt"
}

# The Nomad workload-identity flow INTO Vault: the jwt-nomad auth method + its
# roles. The Vault-side twin of module.consul_nomad_wi. NB module.vault_nomad
# above is the OPPOSITE direction (Vault minting Nomad mgmt tokens); this is Nomad
# allocs logging in to Vault. The accessor-templated nomad-workloads policy is
# owned by the module (it must embed the mount accessor), as is raft-snapshots
# (the raft-snapshotter role opts in via owned_policies). Must exist before
# Nomad's vault{} default_identity goes live (see module).
module "vault_nomad_wi" {
  source = "./modules/vault/nomad-wi"

  auth_method_path = "jwt-nomad"
  default_role     = "nomad-workloads"
  # Vault reads its co-located Nomad agent's JWKS, not the cluster DNS name.
  nomad_jwks_url = "https://localhost:4646/.well-known/jwks.json"
  bound_audience = "vault.io"

  roles = {
    "nomad-workloads" = {
      # The per-workload KV policy is the module's accessor-templated one.
      include_templated_policy = true
      token_policies           = []
    }
    "raft-snapshotter" = {
      # raft-snapshots is owned by the module (modules/vault/nomad-wi/policies) —
      # only this role uses it.
      token_policies = []
      owned_policies = ["raft-snapshots.hcl"]
      # This role hands out Consul + Nomad management tokens, so pin it to the one
      # job that's meant to use it. Nomad's workload-identity nomad_job_id claim is
      # the PARENT job id even for a periodic child — the timestamped child id shows
      # up in the alloc's Job ID and in `sub`, but NOT in this claim — so match the
      # bare parent name (exact, no glob needed).
      bound_claims = {
        nomad_job_id = "cluster-config-snapshotter"
      }
    }
  }
}

module "nomad_oidc" {
  source = "./modules/nomad/oidc"

  nomad_address      = local.nomad_address
  auth_method_name   = "pocket-id"
  oidc_discovery_url = local.oidc_discovery_url
  oidc_client_id     = var.nomad_oidc_client_id
  oidc_client_secret = var.nomad_oidc_client_secret
  bind_policy_name   = "admin"
}

# The Vault Consul secrets engine — mints break-glass Consul management tokens
# (bin/supercow). Mirrors module.vault_nomad; needs a Consul management token
# in CONSUL_HTTP_TOKEN (see providers.tf).
module "vault_consul" {
  source = "./modules/vault/consul"

  backend           = "consul"
  consul_address    = local.consul_address
  engine_token_name = "vault-consul-secrets-engine"
  role_name         = "mgmt"
}

# The baseline Consul ACL layer: the anonymous-token attachment and the four
# non-expiring daemon tokens (also stashed in Vault KV for the Ansible roles).
# The module owns these baseline policies (modules/consul/acl/policies) since it's
# their only consumer; the daemon-token set and anonymous policy are its defaults.
module "consul_acl" {
  source = "./modules/consul/acl"
}

# The Nomad workload-identity flow into Consul: the nomad-workloads JWT auth
# method, the per-service + serviceless binding rules, and the nomad-tasks role.
# Apply this BEFORE Nomad's consul{} gets its identity blocks (see the module).
module "consul_nomad_wi" {
  source = "./modules/consul/nomad-wi"

  nomad_jwks_url = local.nomad_jwks_url
  home_ca_file   = var.home_ca_file
  # nomad-tasks and the task-identity policies below are owned by the module
  # (modules/consul/nomad-wi/policies) — it's their only consumer.

  # Task identities that need more than the read-only nomad-tasks role. The two
  # Traefik ingresses run connectaware and fetch their own Connect leaf cert
  # (service:write on their service); Prometheus scrapes Consul's agent metrics
  # (agent:read). Prometheus's task shares job "monitoring" and task name
  # "server" with blackbox-exporter, but only the prometheus task carries a
  # consul{} block, so it's the only one that ever mints this token.
  task_identity_roles = {
    traefik = {
      policy_file = "traefik.hcl"
      selector    = "value.nomad_job_id == \"traefik\" and \"nomad_service\" not in value"
    }
    traefik-ingress = {
      policy_file = "traefik-ingress.hcl"
      selector    = "value.nomad_job_id == \"traefik-ingress\" and \"nomad_service\" not in value"
    }
    prometheus = {
      policy_file = "prometheus.hcl"
      selector    = "value.nomad_job_id == \"monitoring\" and value.nomad_task == \"server\" and \"nomad_service\" not in value"
    }
  }
}

# The mesh config-entry layer. Currently just an empty proxy-defaults/global to
# silence the not-found ERROR the Connect/Envoy bootstrap logs when it fetches
# global proxy defaults that don't exist. Needs the same Consul management token
# in CONSUL_HTTP_TOKEN as the other Consul modules (see providers.tf).
module "consul_mesh" {
  source = "./modules/consul/mesh"
}

output "vault_pki_backend" {
  value = module.vault_pki.backend
}

output "vault_pki_role" {
  value = module.vault_pki.role_name
}

output "vault_pki_int_backend" {
  value = module.vault_pki_int.backend
}

output "vault_pki_int_role" {
  value = module.vault_pki_int.role_name
}

output "vault_pki_int_internal_backend" {
  value = module.vault_pki_int_internal.backend
}

output "vault_pki_int_internal_role" {
  value = module.vault_pki_int_internal.role_name
}

output "vault_pki_int_connect_backend" {
  value = module.vault_pki_int_connect.backend
}

output "consul_connect_ca_role_id" {
  description = "role_id for Consul servers' connect.ca_config auth_method. Also in Vault KV (kv/consul/connect-ca), which the consul role reads."
  value       = module.vault_pki_int_connect.role_id
}

output "vault_ssh_backend" {
  value = module.vault_ssh.backend
}

output "vault_ssh_role" {
  value = module.vault_ssh.role_name
}

output "vault_approle_role_id" {
  description = "Confirm this equals os/etc/vault-agent.d/agent.roleid after import."
  value       = module.vault_approle.role_id
}

output "vault_oidc_path" {
  value = module.vault_oidc.path
}

output "vault_oidc_accessor" {
  value = module.vault_oidc.accessor
}

output "vault_nomad_backend" {
  value = module.vault_nomad.backend
}

output "vault_nomad_role" {
  value = module.vault_nomad.role_name
}

output "vault_nomad_wi_auth_method_path" {
  value = module.vault_nomad_wi.auth_method_path
}

output "vault_nomad_wi_roles" {
  value = module.vault_nomad_wi.role_names
}

output "nomad_oidc_auth_method" {
  value = module.nomad_oidc.auth_method_name
}

output "vault_consul_backend" {
  value = module.vault_consul.backend
}

output "vault_consul_role" {
  value = module.vault_consul.role_name
}

output "consul_daemon_token_accessors" {
  description = "Map of daemon token name -> accessor (safe to expose; the secrets are in Vault KV / state)."
  value       = module.consul_acl.daemon_token_accessors
}

output "consul_nomad_wi_auth_method" {
  value = module.consul_nomad_wi.auth_method_name
}
