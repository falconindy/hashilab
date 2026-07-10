# ── Global proxy defaults ────────────────────────────────────────────────────
# An empty proxy-defaults/global config entry. Nothing here tunes the mesh; its
# only job is to exist. The Connect/Envoy bootstrap path fetches
# GET /v1/config/proxy-defaults/global on every sidecar setup, and with no entry
# present Consul logs that miss as an ERROR ("Config entry not found for
# proxy-defaults / global") on a loop. Creating the entry turns those 404s into
# 200s and silences the noise — it does not change any proxy behaviour.
#
# This is a mesh config entry (same category as intentions), the first one owned
# by tofu. Add real defaults (protocol, mesh-gateway mode, envoy prometheus bind
# addr, …) to config_json alongside the empty maps below if the mesh ever needs them.
resource "consul_config_entry" "proxy_defaults" {
  kind = "proxy-defaults"
  name = "global"

  # Consul's API normalizes a proxy-defaults entry by adding these four empty
  # sub-objects on read-back. Set them explicitly so config_json matches what
  # Consul returns — otherwise every plan shows a perpetual in-place diff trying
  # to strip them, and Consul re-adds them on the next read.
  config_json = jsonencode({
    AccessLogs       = {}
    Expose           = {}
    MeshGateway      = {}
    TransparentProxy = {}
  })
}
