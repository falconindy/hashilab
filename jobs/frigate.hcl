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

      port "http" {
        to = 5000
      }

      port "rtsp" {
        static = 8554
      }

      port "webrtc" {
        static = 8555
      }
    }

    task "frigate" {
      driver = "podman"

      config {
        image = "ghcr.io/blakeblackshear/frigate:0.16.3"

        network_mode = "host"
        ports        = ["http", "rtsp", "webrtc"]

        shm_size = "1g"

        devices = [
          "/dev/dri",
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
        cpu    = 500
        memory = 2048
      }

      env {
        TZ = "America/New_York"
      }

      service {
        name         = "frigate"
        port         = "http"
        address_mode = "host"

        check {
          type     = "http"
          path     = "/"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
