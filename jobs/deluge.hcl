job "deluge" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "A lightweight, cross-platform BitTorrent client"
    link {
      label = "Upstream"
      url   = "https://deluge-torrent.org"
    }
    link {
      label = "GitHub"
      url   = "https://github.com/deluge-torrent/deluge"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/r/linuxserver/deluge"
    }
  }

  group "deluge" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "envoy_metrics_deluge" { to = 9102 }
      port "envoy_metrics_inbound" { to = 9103 }
    }

    task "server" {
      driver = "docker"

      config {
        # pinned at r1-ls364 due to upstream problems: https://github.com/linuxserver/docker-deluge/issues/229
        image = "linuxserver/deluge:amd64-2.2.0-ls381"
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
      ]

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics_deluge}"
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
      port = 52520

      tags = [
        "traefik-ingress.enable=true",
        "traefik-ingress.tcp.routers.${NOMAD_JOB_NAME}.rule=HostSNI(`*`)",
        "traefik-ingress.tcp.routers.${NOMAD_JOB_NAME}.entrypoints=deluge",
      ]

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
