template {
  source      = "/etc/nomad.d/tls.tpl"
  destination = "/etc/nomad.d/tls.crt"
  user        = "nomad"
  group       = "nomad"
  exec = {
    command = ["systemctl", "reload", "nomad"]
  }
}
