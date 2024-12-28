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
        image        = "esphome/esphome:2024.12.2"
        network_mode = "host"
        privileged   = "true"
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
          "traefik.http.routers.${NOMAD_JOB_NAME}.rule=Host(`${NOMAD_JOB_NAME}.falconindy.com`)",
          "traefik.http.routers.${NOMAD_JOB_NAME}.entrypoints=https",
          "traefik.http.routers.${NOMAD_JOB_NAME}.tls.certresolver=letsEncrypt",
        ]

        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }

      env {
        USERNAME = "dashboard"
        PASSWORD = "${var.esphome_password}"
      }

      resources {
        cpu    = 1000
        memory = 2048
      }
    }
  }
}

variable esphome_password {
  type = string
}
