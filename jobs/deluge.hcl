job "deluge" {
  datacenters = ["dc1"]
  type        = "service"

  group "deluge" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "envoy_metrics" { to = 9102 }
      port "envoy_metrics_inbound" { to = 9103 }
    }

    task "server" {
      driver = "podman"

      config {
        image = "linuxserver/deluge:amd64-2.2.0"
        volumes = [
          "/clusterdata/media:/media:rw",
          "/clusterdata/deluge:/config:rw",
        ]
      }

      env {
        PUID = 911
        PGID = 911
      }

      resources {
        cpu    = 200
        memory = 1024
      }
    }

    service {
      name = "deluge"
      port = 8112

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

    service {
      name = "deluge-inbound"
      port = 6881

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics_inbound}"
      }

      connect {
        sidecar_service {
          proxy {
            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9103"
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
    }
  }
}
