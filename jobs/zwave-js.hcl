job "zwave-js" {
  constraint {
    attribute = "${meta.has_zwave}"
    operator  = "="
    value     = "true"
  }

  group "zwave-js" {
    network {
      mode = "bridge"

      port "http" {
        to = 8091
      }

      port "ws" {
        static = 3000
      }
    }

    volume "zwavejs" {
      type            = "csi"
      read_only       = false
      source          = "zwavejs"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    task "zwave-js" {
      driver = "docker"

      kill_signal = "SIGINT"

      config {
        image = "zwavejs/zwave-js-ui:9.29.0"
        ports = ["http", "ws"]

        volumes = [
          # "/dev/serial/by-id/usb-Zooz_800_Z-Wave_Stick_533D004242-if00:/dev/zwave"
        ]
      }

      volume_mount {
        volume      = "zwavejs"
        destination = "/usr/src/app/store"
        read_only   = false
      }

      env {
        SESSION_SECRET = "${var.zwave_session_secret}"
        TZ             = "America/New_York"
      }

      service {
        port = "http"
        name = "zwavejs"

        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}

variable zwave_session_secret {
  type = string
}
