template {
  source      = "/etc/vault-agent.d/consul-server.tpl"
  destination = "/etc/consul.d/server.crt"
  user        = "consul"
  group       = "consul"
  exec = {
    command = ["systemctl", "reload", "consul"]
  }
}
