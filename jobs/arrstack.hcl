job "arrstack" {
  datacenters = ["dc1"]
  type        = "service"

  group "arrstack" {
    count = 1

    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

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

    task "await-deluge" {
      driver = "podman"

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
      driver = "podman"

      config {
        image = "linuxserver/prowlarr:2.0.5"
        ports = ["prowlarr"]
        volumes = [
          "/etc/ssl/certs:/etc/ssl/certs:ro",
          "/clusterdata/media:/media",
          "/clusterdata/prowlarr:/config",
        ]
      }

      env {
        PUID = 911
        PGID = 911
      }

      service {
        name         = "prowlarr"
        port         = "prowlarr"
        address_mode = "host"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.${NOMAD_TASK_NAME}.rule=Host(`${NOMAD_TASK_NAME}.service.home`)",
          "traefik.http.routers.${NOMAD_TASK_NAME}.entrypoints=https",
          "traefik.http.routers.${NOMAD_TASK_NAME}.tls.certresolver=vault",
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
        memory = 512
      }
    }

    task "radarr" {
      driver = "podman"

      config {
        image = "linuxserver/radarr:5.28.0"
        ports = ["radarr"]
        volumes = [
          "/etc/ssl/certs:/etc/ssl/certs:ro",
          "/clusterdata/media:/media",
          "/clusterdata/radarr:/config",
        ]
      }

      env {
        PUID = 911
        PGID = 911
      }

      service {
        name         = "radarr"
        port         = "radarr"
        address_mode = "host"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.${NOMAD_TASK_NAME}.rule=Host(`${NOMAD_TASK_NAME}.service.home`)",
          "traefik.http.routers.${NOMAD_TASK_NAME}.entrypoints=https",
          "traefik.http.routers.${NOMAD_TASK_NAME}.tls.certresolver=vault",
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
        memory = 512
      }
    }

    task "sonarr" {
      driver = "podman"

      config {
        image = "linuxserver/sonarr:4.0.15"
        ports = ["sonarr"]
        volumes = [
          "/etc/ssl/certs:/etc/ssl/certs:ro",
          "/clusterdata/media:/media",
          "/clusterdata/sonarr:/config",
        ]
      }

      env {
        PUID = 911
        PGID = 911
      }

      service {
        port         = "sonarr"
        name         = "sonarr"
        address_mode = "host"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.${NOMAD_TASK_NAME}.rule=Host(`${NOMAD_TASK_NAME}.service.home`)",
          "traefik.http.routers.${NOMAD_TASK_NAME}.entrypoints=https",
          "traefik.http.routers.${NOMAD_TASK_NAME}.tls.certresolver=vault",
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
        memory = 512
      }
    }
  }
}
