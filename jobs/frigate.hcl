job "frigate" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${meta.has_quicksync}"
    operator  = "="
    value     = "true"
  }

  group "server" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "rtsp" {
        static = 8554
      }

      port "webrtc" {
        static = 8555
      }

      port "envoy_metrics" { to = 9102 }
    }

    task "frigate" {
      driver = "docker"

      config {
        image = "ghcr.io/blakeblackshear/frigate:0.16.4"
        ports = ["rtsp", "webrtc"]

        shm_size = 1048576000

        devices = [
          {
            host_path      = "/dev/dri",
            container_path = "/dev/dri",
          },
        ]

        volumes = [
          "/clusterdata/frigate/config:/config",
          "/clusterdata/frigate/media:/media/frigate",
        ]
      }

      vault {}

      template {
        data        = <<EOF
          {{ with secret "kv/data/default/frigate" }}
            FRIGATE_MQTT_USER="frigate"
            FRIGATE_MQTT_PASSWORD="{{ .Data.data.mqtt_password }}"
            FRIGATE_NURSERY_PASSWORD="{{ .Data.data.nursery_password }}"
            FRIGATE_LIVINGROOM_PASSWORD="{{ .Data.data.livingroom_password }}"
          {{ end }}
        EOF
        destination = "secrets/auth.env"
        env         = true
      }

      resources {
        cpu    = 5000
        memory = 2048
      }

      env {
        TZ = "America/New_York"
      }
    }

    service {
      name = "frigate"
      port = 5000

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

            upstreams {
              destination_name = "mosquitto"
              local_bind_port  = 1883
            }
          }
        }

        sidecar_task {
          resources {
            cpu    = 300
            memory = 96
          }
        }
      }

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
        expose   = true
      }
    }
  }
}
