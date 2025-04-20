job "arrstack" {
  datacenters = ["dc1"]
  type        = "service"

  group "arrstack" {
    count = 1

    network {
      mode = "bridge"

      port "sonarr" {
        to = 8989
      }

      port "radarr" {
        to = 7878
      }

      port "prowlarr" {
        to = 9696
      }
    }

    volume "media" {
      type            = "csi"
      read_only       = false
      source          = "media"
      access_mode     = "multi-node-multi-writer"
      attachment_mode = "file-system"
    }

    volume "sonarr-config" {
      type            = "csi"
      read_only       = false
      source          = "sonarr-config"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    volume "radarr-config" {
      type            = "csi"
      read_only       = false
      source          = "radarr-config"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    volume "prowlarr-config" {
      type            = "csi"
      read_only       = false
      source          = "prowlarr-config"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    task "await-deluge" {
      driver = "docker"

      config {
        image   = "busybox:latest"
        command = "sh"
        args = [
          "-c",
          "echo -n 'Waiting for deluge'; until nslookup deluge.service.home 2>&1 >/dev/null; do echo -n .; sleep 2; done; echo; echo done"
        ]
      }

      resources {
        cpu    = 100
        memory = 128
      }

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }
    }

    task "prowlarr" {
      driver = "docker"

      config {
        image = "linuxserver/prowlarr:1.34.1"
        ports = ["prowlarr"]
      }

      volume_mount {
        volume      = "media"
        destination = "/media"
        read_only   = false
      }

      volume_mount {
        volume      = "prowlarr-config"
        destination = "/config"
        read_only   = false
      }

      env {
        PUID = 911
        PGID = 911
      }

      service {
        name = "prowlarr"
        port = "prowlarr"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.${NOMAD_TASK_NAME}.rule=Host(`${NOMAD_TASK_NAME}.service.home`)",
          "traefik.http.routers.${NOMAD_TASK_NAME}.entrypoints=http",
        ]
        check {
          type     = "http"
          path     = "/"
          interval = "10s"
          timeout  = "5s"
        }
      }

      resources {
        cpu    = 100
        memory = 1024
      }
    }

    task "radarr" {
      driver = "docker"

      config {
        image = "linuxserver/radarr:5.22.4"
        ports = ["radarr"]
      }

      env {
        PUID = 911
        PGID = 911
      }

      volume_mount {
        volume      = "media"
        destination = "/media"
        read_only   = false
      }

      volume_mount {
        volume      = "radarr-config"
        destination = "/config"
        read_only   = false
      }

      service {
        name = "radarr"
        port = "radarr"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.${NOMAD_TASK_NAME}.rule=Host(`${NOMAD_TASK_NAME}.service.home`)",
          "traefik.http.routers.${NOMAD_TASK_NAME}.entrypoints=http",
        ]
        check {
          type     = "http"
          path     = "/"
          interval = "10s"
          timeout  = "5s"
        }
      }

      resources {
        cpu    = 100
        memory = 1024
      }
    }

    task "sonarr" {
      driver = "docker"

      config {
        image = "linuxserver/sonarr:4.0.14"
        ports = ["sonarr"]
      }

      env {
        PUID = 911
        PGID = 911
      }

      volume_mount {
        volume      = "media"
        destination = "/media"
        read_only   = false
      }

      volume_mount {
        volume      = "sonarr-config"
        destination = "/config"
        read_only   = false
      }

      service {
        port = "sonarr"
        name = "sonarr"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.${NOMAD_TASK_NAME}.rule=Host(`${NOMAD_TASK_NAME}.service.home`)",
          "traefik.http.routers.${NOMAD_TASK_NAME}.entrypoints=http",
        ]
        check {
          type     = "http"
          path     = "/"
          interval = "10s"
          timeout  = "5s"
        }
      }

      resources {
        cpu    = 100
        memory = 1024
      }
    }
  }
}
