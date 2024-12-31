# Full configuration options can be found at https://www.consul.io/docs/agent/config

datacenter = "dc1"

data_dir      = "/opt/consul"
enable_syslog = true
log_level     = "WARN"

server             = true
bootstrap_expect   = 3
leave_on_terminate = true

ui_config {
  enabled = true
}

connect {
  enabled = true
}

client_addr    = "0.0.0.0"
advertise_addr = "{{ GetInterfaceIP \"enp1s0\" }}"
bind_addr      = "{{ GetInterfaceIP \"enp1s0\" }}"
retry_join     = ["nomad0.local", "nomad1.local", "nomad2.local"]
