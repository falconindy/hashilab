job "tailscale" {
  datacenters = ["dc1"]
  type        = "service"

  group "networking" {
    count = 1

    volume "tailscale" {
      type      = "csi"
      read_only = false

      source          = "tailscale"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    task "tailscale" {
      driver = "docker"
      config {
        image        = "tailscale/tailscale:v1.78.3"
        entrypoint   = ["/local/start.sh"]
        network_mode = "host"
        force_pull   = true
        privileged   = true
        cap_add      = ["NET_ADMIN", "NET_RAW"]
        volumes = [
          "/dev/net/tun:/dev/net/tun",
        ]
      }

      volume_mount {
        volume      = "tailscale"
        destination = "/var/lib/tailscale"
        read_only   = false
      }

      template {
        data        = <<EOH
#!/bin/sh

function up() {
    until /usr/local/bin/tailscale up \
        --snat-subnet-routes=false \
        --auth-key=${var.tailscale_auth_key} \
        --advertise-exit-node \
        --advertise-routes=10.0.1.0/24,10.0.20.0/24,10.0.100.0/24 \
        --hostname="homelab"
    do
        sleep 0.1
    done

}

# send this function into the background
up &

exec tailscaled --tun=userspace-networking --statedir="/var/lib/tailscale/tailscaled.state"
EOH
        destination = "local/start.sh"
        env         = false
        perms       = 755
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}

variable "tailscale_auth_key" {
  type = string
}

