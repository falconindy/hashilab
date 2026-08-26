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

      kill_timeout = "30s"

      config {
        image = "homeassistant/home-assistant:2026.8.3"

        cap_add      = ["NET_RAW"]
        cap_drop     = ["all"]
        security_opt = ["no-new-privileges=true"]

        volumes = [
          "/run/dbus:/run/dbus",
          "/etc/ssl/certs/ca-certificates.crt:/etc/ssl/certs/ca-certificates.crt:ro",
          "/clusterdata/homeassistant:/config:rw",
        ]
      }

      env {
        TZ                    = "America/New_York"
        REQUESTS_CA_BUNDLE    = "/etc/ssl/certs/ca-certificates.crt"
        S6_SERVICES_GRACETIME = "30000"
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
        "traefik-ingress.enable=true",
      ]

      connect {
        sidecar_service {
          proxy {
            # It would be nice to use transparent_proxy, but the netns
            # introduced by it messes with HA's service discovery.
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
              destination_name = "postgres"
              local_bind_port  = 5432
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
