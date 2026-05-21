job "jellyfin" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${meta.has_quicksync}"
    operator  = "="
    value     = "true"
  }

  group "jellyfin" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "discovery" {
        static = 7359
      }

      port "envoy_metrics" { to = 9102 }
    }

    task "server" {
      driver = "docker"

      config {
        image = "jellyfin/jellyfin:10.11.9"
        ports = ["discovery"]

        volumes = [
          "/etc/ssl/certs:/etc/ssl/certs:ro",
          "/clusterdata/jellyfin:/config:rw",
          "/clusterdata/media:/media:rw",
        ]

        devices = [
          {
            host_path      = "/dev/dri",
            container_path = "/dev/dri",
          },
        ]
      }

      env {
        JELLYFIN_PublishedServerUrl = "https://jellyfin.service.home"
        PUID                        = 911
        PGID                        = 911
      }

      resources {
        cpu    = 500
        memory = 2048
      }
    }

    service {
      name = "jellyfin"
      port = 8096

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=true",
        "traefik.http.routers.${NOMAD_JOB_NAME}.entrypoints=https,http",
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
        path     = "/health"
        interval = "10s"
        timeout  = "2s"
        expose   = true
      }
    }
  }
}
