job "zwave-js" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${meta.has_zwave}"
    operator  = "="
    value     = "true"
  }

  group "zwave-js" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "http" {
        to = 8091
      }

      port "ws" {
        static = 3000
      }
    }

    task "server" {
      driver = "podman"

      kill_signal = "SIGINT"

      config {
        image = "zwavejs/zwave-js-ui:11.8.2"
        ports = ["http", "ws"]

        volumes = [
          "/clusterdata/zwave-js:/usr/src/app/store:rw",
        ]

        devices = [
          "/dev/serial/by-id/usb-Zooz_800_Z-Wave_Stick_533D004242-if00:/dev/zwave:rw",
        ]
      }

      resources {
        cpu    = 100
        memory = 300
      }

      service {
        port         = "http"
        name         = "zwave-js"
        address_mode = "host"
        tags = [
          "traefik.enable=true",
        ]

        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }

      vault {}

      template {
        data        = <<EOF
          {{ with secret "kv/data/default/zwave-js" }}
            SESSION_SECRET="{{ .Data.data.session_secret }}"
          {{ end }}
        EOF
        destination = "secrets/auth.env"
        env         = true
      }
    }
  }
}
