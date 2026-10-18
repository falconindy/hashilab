template {
  source      = "/etc/vault-agent.d/vault-server.tpl"
  destination = "/etc/vault.d/certs/server.crt"
  user        = "vault"
  group       = "vault"
  exec = {
    command = ["systemctl", "reload", "vault"]
  }
}
