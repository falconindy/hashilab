job "deluge" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${attr.unique.network.ip-address}"
    operator  = "="
    value     = "10.0.100.102"
  }

  group "deluge" {
    count = 1

    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "deluge-inbound" {
        static = 6881
      }

      port "envoy_metrics" { to = 9102 }
    }

    task "server" {
      driver = "podman"

      config {
        image = "linuxserver/deluge:amd64-2.2.0"
        ports = ["deluge-inbound"]
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
      name         = "deluge"
      port         = 8112

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
