job "homeassistant" {
  datacenters = ["dc1"]
  type        = "service"

  group "homeassistant" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "http" {
        # Would be nice to use port mapping but we can't use a true bridge
        # without setting up an mDNS repeater or addressing ESPHome devices in
        # another way.
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

    task "server" {
      driver = "podman"
      config {
        image        = "homeassistant/home-assistant:2025.10.1"
        network_mode = "host"
        ports        = ["http"]
        volumes = [
          "/run/dbus:/run/dbus",
          "/etc/ssl/certs:/etc/ssl/certs:ro",
        ]
      }

      volume_mount {
        volume      = "homeassistant"
        destination = "/config"
        read_only   = false
      }

      env {
        TZ = "America/New_York"
      }

      service {
        port         = "http"
        address_mode = "host"
        name         = "homeassistant"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.${NOMAD_JOB_NAME}-public.rule=Host(`hass.falconindy.com`)",
          "traefik.http.routers.${NOMAD_JOB_NAME}-public.entrypoints=public",
          "traefik.http.routers.${NOMAD_JOB_NAME}.rule=Host(`homeassistant.service.home`)",
          "traefik.http.routers.${NOMAD_JOB_NAME}.entrypoints=https",
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
