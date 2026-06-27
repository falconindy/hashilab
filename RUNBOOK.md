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
