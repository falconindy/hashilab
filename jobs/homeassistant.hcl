job "homeassistant" {
  datacenters = ["dc1"]
  type        = "service"

  group "homeassistant" {
    #update {
    #  max_parallel = 1
    #  canary = 1
    #  auto_promote = true
    #  auto_revert = true
    #  min_healthy_time = "30s"
    #  healthy_deadline = "5m"
    #}

    network {
      port "http" {
        static = "8123"
      }
    }

    volume "homeassistant" {
      type      = "csi"
      read_only = false

      source          = "homeassistant"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    task "homeassistant" {
      driver = "docker"
      config {
        image        = "homeassistant/home-assistant:2024.12.5"
        network_mode = "host"
        privileged   = "true"
        ports        = ["http"]
        volumes = [
          "/run/dbus:/run/dbus",
        ]
      }

      volume_mount {
        volume      = "homeassistant"
        destination = "/config"
        read_only   = false
      }

      service {
        port = "http"
        name = "homeassistant"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.${NOMAD_JOB_NAME}.rule=Host(`hass.falconindy.com`)",
          "traefik.http.routers.${NOMAD_JOB_NAME}.entrypoints=https",
          "traefik.http.routers.${NOMAD_JOB_NAME}.tls.certresolver=letsEncrypt",
        ]

        check {
          type     = "http"
          path     = "/manifest.json"
          interval = "10s"
          timeout  = "2s"
        }
      }

      resources {
        cpu    = 1000
        memory = 2048
      }
    }
  }
}
