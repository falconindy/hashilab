terraform {
  # >= 1.10 for ephemeral resources (modules/vault/oidc reads its OIDC client
  # secret from Vault KV as an ephemeral value, never persisted to state).
  required_version = ">= 1.10"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = ">= 5.7"
    }
    # Used only by modules/vault/nomad, to own the dedicated Nomad management
    # token the secrets engine is configured with.
    nomad = {
      source  = "hashicorp/nomad"
      version = ">= 2.4"
    }
    # Drives the Consul ACL layer: policies, the anonymous-token attachment, the
    # daemon tokens, and the nomad-workloads auth method + binding rules. Also
    # owns the dedicated management token the Vault Consul secrets engine uses.
    consul = {
      source  = "hashicorp/consul"
      version = ">= 2.20"
    }
  }

  # Where the state lives is up to you. Local state is fine for a POC, BUT the
  # state file contains secrets — treat it as one. The Consul *management* token
  # the Consul secrets engine uses (module.vault_consul), and the non-expiring
  # Consul daemon tokens (module.consul_acl, also mirrored into Vault KV) all
  # land in state. The Nomad management token's secret_id is fetched ephemerally
  # and never persisted. Use a secure backend and/or OpenTofu state encryption:
  #
  #   encryption {
  #     key_provider "pbkdf2" "k" { passphrase = "..." }   # or a KMS/Vault provider
  #     method "aes_gcm" "m" { keys = key_provider.pbkdf2.k }
  #     state  { method = method.aes_gcm.m }
  #     plan   { method = method.aes_gcm.m }
  #   }
  #
  # State lives in Consul KV at kv path `tofu/hashilab`. It is NOT encrypted (see
  # the encryption block above if you change your mind) — the state holds the
  # Consul management token and daemon secret_ids in plaintext, so the
  # `tofu/hashilab` KV prefix MUST be locked down to management tokens only.
  #
  # The backend reads CONSUL_HTTP_TOKEN from the environment for both the KV
  # writes and the Consul session it takes for state locking — a *management*
  # token (bin/supercow) covers both key:write and session:write. ca_file is
  # pinned here because CONSUL_CACERT isn't always exported; the backend also
  # honours CONSUL_CACERT / CONSUL_HTTP_TOKEN from the environment.
  backend "consul" {
    address = "consul.service.home:8501"
    scheme  = "https"
    path    = "tofu/hashilab"
    ca_file = "/etc/ssl/certs/home.pem"
  }
}
