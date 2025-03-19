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
        image = "zwavejs/zwave-js-ui:10.0.2"
        ports = ["http", "ws"]

        devices = [
          {
            host_path          = "/dev/serial/by-id/usb-Zooz_800_Z-Wave_Stick_533D004242-if00"
            container_path     = "/dev/zwave"
            cgroup_permissions = "rw"
          }
        ]
      }

      resources {
        cpu    = 100
        memory = 300
      }

      service {
        port = "http"
        name = "zwave-js"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.${NOMAD_JOB_NAME}.rule=Host(`${NOMAD_JOB_NAME}.service.home`)",
          "traefik.http.routers.${NOMAD_JOB_NAME}.entrypoints=http",
        ]

        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }

      volume_mount {
        volume      = "zwavejs"
        destination = "/usr/src/app/store"
        read_only   = false
      }

      vault {}

      identity {
        name = "vault_default"
        aud  = ["vault.io"]
        ttl  = "1h"
      }

      template {
        data        = <<EOH
          {{ with secret "kv/data/default/zwave-js" }}
            SESSION_SECRET="{{ .Data.data.session_secret }}"
          {{ end }}
      EOH
        destination = "secrets/auth.env"
        env         = true
      }
    }
  }
}
