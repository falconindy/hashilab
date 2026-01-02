job "valkey" {
  datacenters = ["dc1"]
  type        = "service"

  group "valkey" {
    network {
      mode = "bridge"

      port "db" {
        static = 6379
      }
    }

    task "server" {
      driver = "podman"

      config {
        image        = "valkey/valkey:9.0.1"
        ports        = ["db"]
        network_mode = "host"

        # Uncomment to use a custom config file
        # args = ["valkey-server", "/local/valkey.conf"]
        volumes = [
          "/clusterdata/valkey:/data:rw",
        ]
      }

      # Use a template to create a custom config if needed
      template {
        data        = <<-EOH
          maxmemory 256mb
          maxmemory-policy allkeys-lru
          appendonly yes
        EOH
        destination = "local/valkey.conf"
      }

      resources {
        cpu    = 500 # MHz
        memory = 512 # MB
      }

      service {
        name         = "valkey"
        port         = "db"
        address_mode = "host"

        check {
          name     = "valkey-alive"
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
