job "esphome" {
  datacenters = ["dc1"]
  type        = "service"

  group "esphome" {
    network {
      port "http" {
        static = 6052
      }
    }

    volume "esphome-config" {
      type      = "csi"
      read_only = false

      source          = "esphome-config"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    volume "esphome-cache" {
      type      = "csi"
      read_only = false

      source          = "esphome-cache"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }


    task "dashboard" {
      driver = "docker"
      config {
        image        = "esphome/esphome:2025.2.1"
        network_mode = "host"
        ports        = ["http"]
        volumes = [
          "/etc/localtime:/etc/localtime:ro",
        ]
      }

      volume_mount {
        volume      = "esphome-config"
        destination = "/config"
        read_only   = false
      }

      volume_mount {
        volume      = "esphome-cache"
        destination = "/cache"
        read_only   = false
      }

      service {
        port = "http"
        name = "esphome"
        tags = [
          "traefik.enable=true",
          # http rule is still needed in order for HASS to do whatever polling
          # it does against the /devices endpoint.
          "traefik.http.routers.${NOMAD_JOB_NAME}.rule=Host(`${NOMAD_JOB_NAME}.service.home`)",
          "traefik.http.routers.${NOMAD_JOB_NAME}.entrypoints=http",

          "traefik.http.routers.${NOMAD_JOB_NAME}-https.rule=Host(`${NOMAD_JOB_NAME}.service.home`)",
          "traefik.http.routers.${NOMAD_JOB_NAME}-https.entrypoints=https",
          "traefik.http.routers.${NOMAD_JOB_NAME}-https.tls.certresolver=vault",
        ]

        check {
          type     = "http"
          path     = "/version"
          interval = "10s"
          timeout  = "2s"
        }
      }

      resources {
        cpu    = 500
        memory = 4096
      }
    }
  }
}
