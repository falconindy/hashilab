job "frigate" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${meta.has_quicksync}"
    operator  = "="
    value     = "true"
  }

  group "server" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "http" {
        to = 5000
      }

      port "rtsp" {
        static = 8554
      }

      port "webrtc" {
        static = 8555
      }
    }

    task "frigate" {
      driver = "podman"

      config {
        image = "ghcr.io/blakeblackshear/frigate:0.16.2"

        network_mode = "host"
        ports        = ["http", "rtsp", "webrtc"]

        shm_size = "1g"

        devices = [
          "/dev/dri",
        ]

        volumes = [
          "/clusterdata/frigate/config:/config",
          "/clusterdata/frigate/media:/media/frigate",

          # Temporary cache for recordings - highly recommended for performance
          # You might want to use a separate tmpfs/SSD for this mount on the host.
          #"/mnt/frigate/cache:/tmp/cache",
        ]

      }

      resources {
        cpu    = 500
        memory = 2048
      }

      service {
        name         = "frigate"
        port         = "http"
        address_mode = "host"

        tags = [
          "traefik.enable=true",
        ]

        check {
          type     = "http"
          path     = "/"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
