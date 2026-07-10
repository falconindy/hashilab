# ── Service intentions (the mesh's L4 authorization) ─────────────────────────
# The Connect mesh is default-deny: the `*` destination below denies `*` at
# precedence 5, and every allowed edge is an explicit higher-precedence source.
# These were previously applied out of band with `consul config write`; they now
# live here so the authz graph is version-controlled and drift-detected. Adopt
# the live entries with `tofu import` (see tofu/README.md) — a fresh apply would
# otherwise try to create them and clash with what's running.
#
# Keyed by destination service; each value is the ordered list of sources that
# may reach it. Order matches what's live to keep diffs quiet. `type = "consul"`
# is the only source type here (set explicitly so it doesn't drift against the
# server default). `precedence` is computed by Consul from wildcard specificity,
# so it's never set. Add an edge with a source; add a destination with a key.
locals {
  intentions = {
    "*" = [
      { name = "traefik", action = "allow" },
      { name = "prometheus", action = "allow" },
      { name = "*", action = "deny" },
    ]
    "deluge" = [
      { name = "sonarr", action = "allow" },
      { name = "radarr", action = "allow" },
    ]
    "deluge-inbound" = [
      { name = "traefik-ingress", action = "allow" },
    ]
    "go2rtc" = [
      { name = "homeassistant", action = "allow" },
    ]
    "homeassistant" = [
      { name = "traefik-ingress", action = "allow" },
    ]
    "jackett" = [
      { name = "sonarr", action = "allow" },
      { name = "radarr", action = "allow" },
    ]
    "mosquitto" = [
      { name = "teslamate", action = "allow" },
      { name = "mqtt-explorer", action = "allow" },
      { name = "rtl433", action = "allow" },
      { name = "homeassistant", action = "allow" },
      { name = "maramon", action = "allow" },
    ]
    "nut" = [
      { name = "homeassistant", action = "allow" },
    ]
    "pocket-id" = [
      { name = "traefik-ingress", action = "allow" },
    ]
    "postgres" = [
      { name = "teslamate", action = "allow" },
      { name = "grafana", action = "allow" },
    ]
    "prometheus" = [
      { name = "grafana", action = "allow" },
      { name = "homeassistant", action = "allow" },
    ]
    "victorialogs" = [
      { name = "vector", action = "allow" },
      { name = "grafana", action = "allow" },
    ]
    "zwave-ws" = [
      { name = "homeassistant", action = "allow" },
    ]
  }
}

resource "consul_config_entry_service_intentions" "this" {
  for_each = local.intentions

  name = each.key

  dynamic "sources" {
    for_each = each.value
    content {
      name   = sources.value.name
      type   = "consul"
      action = sources.value.action
    }
  }
}
