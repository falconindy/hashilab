template {
  source      = "/etc/vault-agent.d/vault-server.tpl"
  destination = "/etc/vault.d/server.crt"
  user        = "vault"
  group       = "vault"
  exec = {
    command = ["systemctl", "reload", "vault"]
  }
}

template {
  source      = "/etc/vault-agent.d/vault-client.tpl"
  destination = "/etc/vault.d/client.crt"
  user        = "vault"
  group       = "vault"
  exec = {
    command = ["systemctl", "reload", "vault"]
  }
}
