job "tailscale" {
  datacenters = ["dc1"]
  type        = "service"

  group "networking" {
    count = 1

    network {
      dns {
        servers = ["172.17.0.1"]
      }

      port "http" {}
    }

    task "tailscale" {
      driver = "podman"
      config {
        image        = "tailscale/tailscale:v1.92.5"
        network_mode = "host"
        force_pull   = true
        cap_add      = ["NET_ADMIN", "NET_RAW"]
        volumes = [
          "/clusterdata/tailscale:/var/lib/tailscale:rw"
        ]

        devices = [
          "/dev/net/tun",
        ]
      }

      vault {}

      template {
        data        = <<EOF
          {{ with secret "kv/data/default/tailscale" }}
            TS_AUTHKEY="{{ .Data.data.auth_key }}"
          {{ end }}

          TS_USERSPACE="true"
          TS_STATE_DIR="/var/lib/tailscale/tailscaled.state"
          TS_EXTRA_ARGS="--reset --advertise-exit-node"

          TS_HOSTNAME="homelab"
          TS_ROUTES="10.0.1.0/24,10.0.20.0/24,10.0.100.0/24"

          TS_LOCAL_ADDR_PORT="{{ env "NOMAD_ADDR_http" }}"
          TS_ENABLE_HEALTH_CHECK="true"
          TS_ENABLE_METRICS="true"
        EOF
        destination = "secrets/env"
        env         = true
      }

      service {
        name         = "tailscale"
        port         = "http"
        address_mode = "host"

        check {
          type     = "http"
          path     = "/healthz"
          interval = "10s"
          timeout  = "2s"
        }
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
