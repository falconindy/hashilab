job "maramon" {
  datacenters = ["dc1"]
  type        = "service"

  group "maramon" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "envoy_metrics" { to = 9102 }
    }

    vault {}

    task "server" {
      driver = "docker"

      config {
        image      = "docker-registry.service.home/maramon:latest"
        force_pull = true
      }

      env {
        PORT = 8484
        TZ   = "America/New_York"

        MQTT_HOST     = "mosquitto.virtual.home"
        MQTT_PORT     = 80
        MQTT_USERNAME = "rtl_433"
      }

      template {
        data        = <<EOF
          {{ with secret "kv/data/default/maramon" }}
            HUCKLEBERRY_EMAIL    = "{{ .Data.data.huckleberry_email }}"
            HUCKLEBERRY_PASSWORD = "{{ .Data.data.huckleberry_password }}"
            STREAM_URL           = "{{ .Data.data.stream_url }}"
            MQTT_PASSWORD        = "{{ .Data.data.mqtt_password }}"
          {{ end }}
        EOF
        destination = "secrets/env"
        env         = true
      }

      resources {
        cpu    = 100
        memory = 128
      }

      restart {
        attempts = 5
        delay    = "10s"
        interval = "2m"
        mode     = "delay"
      }
    }

    service {
      name = "maramon"
      port = 8484

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
        path     = "/health"
        interval = "15s"
        timeout  = "3s"
        expose   = true
      }
    }

  }
}
