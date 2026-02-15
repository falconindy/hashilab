job "omada-controller" {
  datacenters = ["dc2"]
  type        = "service"

  group "omada-controller" {
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
      port "devicemonitor" { static = 29817 }
    }

    task "omada-controller" {
      driver = "docker"
      config {
        image        = "mbentley/omada-controller:6.1.0.19-openj9"
        network_mode = "host"
        volumes = [
          "/clusterdata/omada-controller/data:/opt/tplink/EAPController/data:rw",
          "/clusterdata/omada-controller/logs:/opt/tplink/EAPController/logs:rw",
          "/clusterdata/omada-controller/cert:/cert:ro",
        ]
      }

      service {
        name = "omada-controller"
        port = "manage_https"

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
