job "radarr" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "A movie collection manager for Usenet and BitTorrent users"
    link {
      label = "Upstream"
      url   = "https://radarr.video"
    }
    link {
      label = "GitHub"
      url   = "https://github.com/Radarr/Radarr"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/r/linuxserver/radarr"
    }
  }

  group "radarr" {
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

    task "radarr" {
      driver = "docker"

      config {
        image = "linuxserver/radarr:6.3.0"
        volumes = [
          "/clusterdata/media:/media",
          "/clusterdata/radarr:/config",
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
      name = "radarr"
      port = 7878

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
            transparent_proxy {
              # Sonarr makes calls to the outside world.
              no_dns = true
            }

            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9102"
            }

            expose {
              path {
                path            = "/metrics"
                protocol        = "http"
                local_path_port = 9102
                listener_port   = "envoy_metrics"
              }
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
