template {
  source      = "/etc/consul.d/tls.tpl"
  destination = "/etc/consul.d/tls.crt"
  user        = "consul"
  group       = "consul"
  exec = {
    command = ["systemctl", "reload", "consul"]
  }
}
