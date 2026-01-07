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

      port "envoy_metrics" { to = 9102 }
    }

    task "await-deluge" {
      driver = "raw_exec"

      config {
        command = "/bin/sh"
        args = [
          "-c", <<-EOF
            echo 'Waiting for deluge'
            until nslookup deluge.service.home 172.17.0.1; do
              sleep 2
            done
            echo done
          EOF
        ]
      }

      resources {
        cpu    = 50
        memory = 64
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

      resources {
        cpu    = 100
        memory = 512
      }
    }

    service {
      name         = "sonarr"
      port         = 8989
      address_mode = "host"

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=true",
      ]

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}"
      }

      connect {
        sidecar_service {
          proxy {
            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9102"
            }
          }
        }

        sidecar_task {
          resources {
            cpu    = 50
            memory = 48
          }
        }
      }

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "5s"
        expose   = true
      }
    }
  }
}
