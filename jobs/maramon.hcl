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
      user   = "1000:1000"

      config {
        image      = "docker-registry.service.home/maramon:latest"
        force_pull = true

        cap_drop     = ["all"]
        security_opt = ["no-new-privileges=true"]
      }

      env {
        PORT = 8484
        TZ   = "America/New_York"

        MQTT_HOST     = "mosquitto.virtual.home"
        MQTT_USERNAME = "rtl_433"
      }

      template {
        data        = <<-EOF
          {{ with (secret "kv/data/default/maramon").Data.data }}
            HUCKLEBERRY_EMAIL    = "{{ .huckleberry_email }}"
            HUCKLEBERRY_PASSWORD = "{{ .huckleberry_password }}"
            STREAM_URL           = "{{ .stream_url }}"
            MQTT_PASSWORD        = "{{ .mqtt_password }}"
          {{ end }}
        EOF
        destination = "secrets/env"
        env         = true
      }

      resources {
        cpu        = 100
        memory     = 128
        memory_max = 1024
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
