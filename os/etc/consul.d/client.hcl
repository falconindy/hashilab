service {
  id   = "consul-client"
  name = "consul-client"
  port = 8501

  check {
    id       = "consul-client"
    name     = "Consul HTTPS"
    http     = "https://localhost:8501/v1/status/leader"
    interval = "10s"
    timeout  = "1s"
  }
}
