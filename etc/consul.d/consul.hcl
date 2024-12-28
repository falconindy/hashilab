# Full configuration options can be found at https://www.consul.io/docs/agent/config

datacenter          = "dc1"

data_dir            = "/opt/consul"
enable_syslog       = true
log_level           = "WARN"

server              = true
bootstrap_expect    = 3
leave_on_terminate  = true

encrypt           = "nRNzPgpFDPOo2Sxuz1v7TlDxYCUGwN9LNJ+KO0TfTKY="

ui_config {
  enabled = true
}

connect {
  enabled = true
}

client_addr     = "0.0.0.0"
advertise_addr  = "{{ GetPrivateInterfaces | include \"network\" \"10.0.100.0/24\" | attr \"address\" }}"
bind_addr       = "{{ GetPrivateInterfaces | include \"network\" \"10.0.100.0/24\" | attr \"address\" }}"
retry_join      = ["nomad0.local", "nomad1.local", "nomad2.local"]

# acl {
#   enabled = false
#   default_policy = "allow"
#   down_policy = "extend-cache"
# }
