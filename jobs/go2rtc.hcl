job "go2rtc" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "Ultimate camera streaming application with support for RTSP, WebRTC, HomeKit, and more"
    link {
      label = "GitHub"
      url   = "https://github.com/AlexxIT/go2rtc"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/r/alexxit/go2rtc"
    }
  }

  constraint {
    attribute = "${meta.has_quicksync}"
    operator  = "="
    value     = "true"
  }

  group "go2rtc" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "rtsp" { static = 8554 }
      port "webrtc" { static = 8555 }

      port "envoy_metrics" { to = 9102 }
    }

    vault {}

    task "server" {
      driver = "docker"

      config {
        image = "alexxit/go2rtc:1.9.15"
        ports = ["rtsp", "webrtc"]

        cap_drop     = ["all"]
        security_opt = ["no-new-privileges=true"]

        volumes = [
          "local/go2rtc.yaml:/config/go2rtc.yaml"
        ]

        devices = [
          {
            host_path      = "/dev/dri",
            container_path = "/dev/dri",
          },
        ]
      }

      template {
        data        = <<-EOF
          log:
            level: info

          api:
            listen: ":1984"
            origin: "*"

          rtsp:
            listen: ":8554"

          webrtc:
            listen: ":8555"

            # LAN-only: viewers reach this host address on Wi-Fi or over
            # Tailscale (subnet routes); nothing is published to the internet.
            # Home Assistant's camera views reach go2rtc through the Home
            # Assistant Web Proxy integration (hass-web-proxy), which relays
            # them over HA's own connection. No STUN either: with a single fixed
            # candidate there's no per-session random UDP socket (only 8555
            # is mapped into the container, so pairs on one always failed).
            ice_servers: []

            candidates:
              - {{ env "NOMAD_HOST_ADDR_webrtc" }}

            filters:
              networks: [udp4]

          {{ with (secret "kv/data/default/go2rtc").Data.data }}
          streams:
            nursery:
              - rtsp://{{ .nursery_connection }}/Preview_01_main
              - ffmpeg:nursery#audio=opus#query=log_level=debug
            livingroom:
              - rtsp://{{ .livingroom_connection }}/stream1
              - ffmpeg:livingroom#audio=opus#query=log_level=debug
          {{ end }}
        EOF
        destination = "local/go2rtc.yaml"
      }

      resources {
        cpu    = 1000
        memory = 256
      }

      env {
        TZ = "America/New_York"
      }
    }

    service {
      name = "go2rtc"
      port = 1984

      tags = [
        "traefik.enable=true",
      ]

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}"
      }

      connect {
        sidecar_service {}

        sidecar_task {
          resources {
            cpu    = 100
            memory = 48
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
