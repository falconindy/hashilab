job "buildkit" {
  datacenters = ["dc1"]
  type        = "service"

  group "buildkit" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "buildkit" {
        # running buildkit through a reverse proxy is apparent non-trivial
        # ref: https://github.com/moby/buildkit/issues/1464
        static = 10000
      }
    }

    task "server" {
      driver = "podman"

      config {
        image      = "moby/buildkit:latest"
        ports      = ["buildkit"]
        privileged = true

        args = [
          "--addr=tcp://0.0.0.0:${NOMAD_PORT_buildkit}",
        ]

        volumes = [
          "/etc/ssl/certs:/etc/ssl/certs:ro",
        ]
      }

      resources {
        cpu    = 1000
        memory = 2048
      }
    }

    service {
      name         = "buildkit"
      port         = "buildkit"
      address_mode = "host"

      check {
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"
      }
    }
  }
}
