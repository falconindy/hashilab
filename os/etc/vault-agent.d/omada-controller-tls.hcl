template {
  source      = "/etc/vault-agent.d/omada-controller.tpl"
  destination = "/run/vault-agent/omada-controller/tls.crt"

  # On each (re)issue, push the rendered chain + key into Vault KV. Restarting
  # omada is the Nomad job's responsibility (its template watches the KV secret
  # with change_mode="restart"), not this agent's.
  exec = {
    command = ["/etc/vault-agent.d/omada-push-kv.sh"]
  }
}
