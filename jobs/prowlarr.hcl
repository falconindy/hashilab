job "prowlarr" {
  datacenters = ["dc1"]
  type        = "service"

  group "prowlarr" {
    count = 1

    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "http" {
        to = 9696
      }
    }

    task "await-deluge" {
      driver = "podman"

      config {
        image   = "busybox:latest"
        command = "/bin/sh"
        args = [
          "-c", <<-EOF
            echo -n 'Waiting for deluge'
            until nslookup deluge.service.home 2>&1 >/dev/null; do
              echo -n .
              sleep 2
            done
            echo
            echo done
          EOF
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

    task "server" {
      driver = "podman"

      config {
        image = "linuxserver/prowlarr:2.3.0"
        ports = ["http"]
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
        port         = "http"
        address_mode = "host"
        tags = [
          "traefik.enable=true",
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
