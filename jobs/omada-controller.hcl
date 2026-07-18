job "omada-controller" {
  datacenters = ["dc2"]
  type        = "service"

  ui {
    description = "TP-Link Omada SDN controller for managing network devices"
    link {
      label = "Upstream"
      url   = "https://www.tp-link.com/us/omada-sdn/"
    }
    link {
      label = "GitHub"
      url   = "https://github.com/mbentley/docker-omada-controller"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/r/mbentley/omada-controller"
    }
  }

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

      vault {}

      config {
        image        = "mbentley/omada-controller:6.2.14.11-openj9"
        network_mode = "host"
        volumes = [
          "/clusterdata/omada-controller/data:/opt/tplink/EAPController/data:rw",
          "/clusterdata/omada-controller/logs:/opt/tplink/EAPController/logs:rw",
          # Only the cert subdir, so the task's Vault token (also under
          # secrets/) stays out of the container.
          "secrets/cert:/cert:ro",
        ]
      }

      # The cert is issued and rotated by the omada host's vault-agent, which
      # pushes it into KV (see os/etc/vault-agent.d/omada-controller.tpl). Both
      # blocks read the same KV path, so consul-template coalesces them into one
      # read — always a matched pair. change_mode restart re-imports the keystore
      # (omada only reads /cert at boot) when vault-agent rolls the cert.
      template {
        data        = <<-EOF
          {{- with secret "kv/data/default/omada-controller/cert" }}{{ .Data.data.tls_crt }}{{ end }}
        EOF
        destination = "secrets/cert/tls.crt"
        perms       = "0644"
        change_mode = "restart"
      }

      template {
        data        = <<-EOF
          {{- with secret "kv/data/default/omada-controller/cert" }}{{ .Data.data.tls_key }}{{ end }}
        EOF
        destination = "secrets/cert/tls.key"
        perms       = "0640"
        change_mode = "restart"
      }

      service {
        name = "omada-controller"
        port = "manage_https"

        check {
          type     = "http"
          protocol = "https"
          path     = "/api/v2/anon/info"
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
