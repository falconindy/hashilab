job "adguard" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "A network-wide DNS server that blocks ads and trackers"
    link {
      label = "Upstream"
      url   = "https://adguard.com/en/adguard-home/overview.html"
    }
    link {
      label = "GitHub"
      url   = "https://github.com/AdguardTeam/AdGuardHome"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/r/adguard/adguardhome"
    }
  }

  group "adguard" {
    network {
      mode = "bridge"

      port "dns" { to = 53 }

      port "envoy_metrics" { to = 9102 }
    }

    task "server" {
      driver = "docker"

      config {
        image = "adguard/adguardhome:v0.107.78"

        volumes = [
          "/clusterdata/adguard:/opt/adguardhome/conf:rw",
        ]
      }

      env {
        TZ = "America/New_York"
      }

      resources {
        memory = 128
        cpu    = 50
      }
    }

    service {
      name = "adguard-ui"
      port = 80

      check {
        type     = "http"
        path     = "/login.html"
        interval = "10s"
        timeout  = "5s"
        expose   = true
      }

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
    }

    service {
      name = "adguard-dns"
      port = "dns"

      check {
        type     = "script"
        command  = "nslookup"
        args     = ["www.google.com", "127.0.0.1"]
        interval = "10s"
        timeout  = "5s"
        task     = "server"

        check_restart {
          limit = 3
          grace = "30s"
        }
      }
    }
  }
}
