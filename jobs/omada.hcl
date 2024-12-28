job "omada" {
  group "omada" {
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
      port "http" { to = "8088" }
      port "https" { to = "8043" }
      port "app_discovery" { static = 27001 }
      port "adopt_v1" { static = 29812 }
      port "upgrade_v1" { static = 29813 }
      port "manager_v1" { static = 29811 }
      port "manager_v2" { static = 29814 }
      port "discovery" { static = 29810 }
      port "transfer_v2" { static = 29815 }
      port "rtty" { static = 29816 }
    }

    task "controller" {
      driver = "docker"
      config {
        image        = "mbentley/omada-controller:5.15.6.7"
        privileged   = true
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
        port = "http"
        name = "omada"
        tags = [
          # "traefik.enable=true",
          # "traefik.http.routers.${NOMAD_JOB_NAME}.rule=Host(`${NOMAD_JOB_NAME}.falconindy.com`)",
          # "traefik.http.routers.${NOMAD_JOB_NAME}.entrypoints=https",
          # "traefik.http.routers.${NOMAD_JOB_NAME}.tls.certresolver=letsEncrypt",
          # "traefik.http.services.${NOMAD_JOB_NAME}.loadbalancer.server.port=8088",
        ]

        # check {
        #   type     = "tcp"
        #   interval = "10s"
        #   timeout  = "2s"
        # }
      }

      env {
        PUID               = "508"
        PGID               = "508"
        MANAGE_HTTP_PORT   = "8088"
        MANAGE_HTTPS_PORT  = "8043"
        PORTAL_HTTP_PORT   = "8088"
        PORTAL_HTTPS_PORT  = "8843"
        PORT_APP_DISCOVERY = "27001"
        PORT_ADOPT_V1      = "29812"
        PORT_UPGRADE_V1    = "29813"
        PORT_MANAGER_V1    = "29811"
        PORT_MANAGER_V2    = "29814"
        PORT_DISCOVERY     = "29810"
        PORT_TRANSFER_V2   = "29815"
        PORT_RTTY          = "29816"
        SHOW_SERVER_LOGS   = "true"
        SHOW_MONGODB_LOGS  = "false"
        SSL_CERT_NAME      = "tls.crt"
        SSL_KEY_NAME       = "tls.key"
        TZ                 = "America/New_York"
      }

      resources {
        cpu    = 1000
        memory = 2048
      }
    }
  }
}
