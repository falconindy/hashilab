job "homeassistant" {
  datacenters = ["dc1"]
  type        = "service"

  group "homeassistant" {
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
        image        = "homeassistant/home-assistant:2025.5.3"
        network_mode = "host"
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
          "traefik.http.routers.${NOMAD_JOB_NAME}-internal.rule=Host(`homeassistant.service.home`)",
          "traefik.http.routers.${NOMAD_JOB_NAME}-internal.entrypoints=http",
        ]

        check {
          type     = "http"
          path     = "/manifest.json"
          interval = "10s"
          timeout  = "2s"
        }
      }

      resources {
        cpu    = 500
        memory = 2048
      }
    }
  }
}
