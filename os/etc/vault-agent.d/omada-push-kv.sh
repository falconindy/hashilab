#!/usr/bin/env bash
# Push the vault-agent-rendered omada-controller cert + key into Vault KV, from
# where the omada-controller Nomad job reads them (and restarts on change). Run
# as the exec hook of omada-controller-tls.hcl, so it fires on every (re)issue.
#
# Both keys are written in one `vault kv put`, so the job always reads a matched
# pair. Retention (so old private keys don't pile up) is a set-once concern, done
# out of band after the first push and not re-asserted here — this token only has
# kv/data write, deliberately not metadata:
#   vault kv metadata put -max-versions=3 kv/default/omada-controller/cert
set -euo pipefail

dir=/run/vault-agent/omada-controller

export VAULT_ADDR="https://active.vault.service.home:8200"
VAULT_TOKEN="$(cat /run/vault-agent/token)"
export VAULT_TOKEN

vault kv put kv/default/omada-controller/cert \
  tls_crt=@"${dir}/tls.crt" \
  tls_key=@"${dir}/tls.key"
