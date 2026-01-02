job "sonarr" {
  datacenters = ["dc1"]
  type        = "service"

  group "sonarr" {
    count = 1

    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "http" {
        to = 8989
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
        image = "linuxserver/sonarr:4.0.16"
        ports = ["http"]
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
        name    = "sonarr"
        port    = "http"
        address = "l.service.home"

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
