job "homeassistant" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "A locally controlled home automation platform."
    link {
      label = "Upstream"
      url   = "https://home-assistant.io"
    }
    link {
      label = "GitHub"
      url   = "https://github.com/home-assistant/core"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/r/homeassistant/home-assistant"
    }
  }

  group "homeassistant" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "envoy_metrics" { to = 9102 }
    }

    task "server" {
      driver = "docker"

      config {
        image = "homeassistant/home-assistant:2026.5.1"
        volumes = [
          "/run/dbus:/run/dbus",
          "/etc/ssl/certs:/etc/ssl/certs:ro",
          "/clusterdata/homeassistant:/config:rw",
        ]
      }

      template {
        destination = "local/http.yaml"
        data        = <<-EOF
          server_port: 8123
          use_x_forwarded_for: true
          trusted_proxies:
            - 127.0.0.1/32
            - 10.0.100.0/24
            - 172.16.0.0/12
        EOF
      }

      env {
        TZ                 = "America/New_York"
        REQUESTS_CA_BUNDLE = "/etc/ssl/certs/ca-certificates.crt"
      }

      resources {
        cpu    = 500
        memory = 2048
      }
    }

    service {
      name = "homeassistant"
      port = 8123

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}"
      }

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=true",

        "traefik-ingress.enable=true",
        "traefik-ingress.consulcatalog.connect=true",
      ]

      connect {
        sidecar_service {
          proxy {
            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9102"
            }

            upstreams {
              destination_name = "mosquitto"
              local_bind_port  = 1883
            }
            upstreams {
              destination_name = "go2rtc"
              local_bind_port  = 1984
            }
            upstreams {
              destination_name = "nut"
              local_bind_port  = 3493
            }
            upstreams {
              destination_name = "zwave-ws"
              local_bind_port  = 3000
            }
            upstreams {
              destination_name = "prometheus"
              local_bind_port  = 9090
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
        path     = "/manifest.json"
        interval = "10s"
        timeout  = "2s"
        expose   = true
      }
    }
  }
}
