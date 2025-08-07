job "omada-controller" {
  datacenters = ["dc2"]
  type        = "service"

  group "omada-controller" {
    volume "data" {
      type            = "csi"
      read_only       = false
      source          = "omada-controller-data"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    volume "logs" {
      type            = "csi"
      read_only       = false
      source          = "omada-controller-logs"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    network {
      dns {
        servers = ["172.17.0.1"]
      }

      port "http" { static = 8088 }
      port "manage_https" { static = 8043 }
      port "portal_https" { static = 8843 }
      port "olt" { static = 19810 }
      port "app_discovery" { static = 27001 }
      port "discovery" { static = 29810 }
      port "manager_v1" { static = 29811 }
      port "adopt_v1" { static = 29812 }
      port "upgrade_v1" { static = 29813 }
      port "manager_v2" { static = 29814 }
      port "transfer_v2" { static = 29815 }
      port "rtty" { static = 29816 }
    }

    task "omada-controller" {
      driver = "podman"
      config {
        image        = "mbentley/omada-controller:5.15.24.19"
        network_mode = "host"
      }

      volume_mount {
        volume      = "data"
        destination = "/opt/tplink/EAPController/data"
        read_only   = false
      }

      volume_mount {
        volume      = "logs"
        destination = "/opt/tplink/EAPController/logs"
        read_only   = false
      }

      service {
        port         = "http"
        address_mode = "host"
        name         = "omada-controller"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.${NOMAD_TASK_NAME}.rule=Host(`${NOMAD_TASK_NAME}.service.home`)",
          # "traefik.http.routers.${NOMAD_TASK_NAME}.entrypoints=https",
          # "traefik.http.routers.${NOMAD_TASK_NAME}.tls.certresolver=vault",
        ]

        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }

      env {
        PUID = "508"
        PGID = "508"

        SHOW_SERVER_LOGS  = "true"
        SHOW_MONGODB_LOGS = "false"
        SSL_CERT_NAME     = "tls.crt"
        SSL_KEY_NAME      = "tls.key"
        TZ                = "America/New_York"
      }

      resources {
        cpu    = 200
        memory = 2048
      }
    }
  }
}
