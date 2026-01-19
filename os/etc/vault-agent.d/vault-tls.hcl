template {
  source      = "/etc/vault.d/tls.tpl"
  destination = "/etc/vault.d/tls.crt"
  user        = "vault"
  group       = "vault"
  exec = {
    command = ["systemctl", "reload", "vault"]
  }
}
