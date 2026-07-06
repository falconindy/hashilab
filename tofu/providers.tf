# The Vault provider reads VAULT_ADDR and VAULT_TOKEN from the environment. Log
# in first:
#
#   vault login -method=oidc            # passkey -> admin token
#   export VAULT_ADDR=https://vault.service.home:8200
#   tofu -chdir=tofu plan
#
# No credentials are hardcoded here on purpose.
provider "vault" {}

# The Nomad provider reads NOMAD_ADDR and NOMAD_TOKEN from the environment. It is
# only exercised by modules/vault/nomad, which creates the dedicated management
# token for the Vault Nomad secrets engine. Creating ACL tokens requires a Nomad
# *management* token — the day-to-day OIDC admin token (a policy bind) can't do
# it — so NOMAD_TOKEN must be a management token (break-glass / bootstrap):
#
#   export NOMAD_ADDR=https://nomad.service.home:4646
#   export NOMAD_TOKEN=<a Nomad management token>
#
# If you aren't managing modules/vault/nomad, this provider stays unused and no
# Nomad token is needed.
provider "nomad" {}
