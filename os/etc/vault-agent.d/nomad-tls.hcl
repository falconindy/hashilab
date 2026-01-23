template {
  source      = "/etc/vault-agent.d/nomad-server.tpl"
  destination = "/etc/nomad.d/server.crt"
  user        = "nomad"
  group       = "nomad"
  exec = {
    command = ["systemctl", "reload", "nomad"]
  }
}
