job "stirling" {
  datacenters = ["dc1"]
  type        = "service"

  group "stirling" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "http" {
        to = 8080
      }
    }

    task "server" {
      driver = "podman"
      config {
        image = "stirlingtools/stirling-pdf:2.0.1-ultra-lite"
        ports = ["http"]
        volumes = [
          "/clusterdata/stirling/tessdata:/usr/share/tessdata:rw",
          "/clusterdata/stirling/configs:/configs:rw",
          "/clusterdata/stirling/customfiles:/customfiles:rw",
          "/clusterdata/stirling/logs:/logs:rw",
          "/clusterdata/stirling/pipeline:/pipeline:rw",
        ]
      }

      env {
        TZ = "America/New_York"
      }

      resources {
        cpu    = 100
        memory = 512
      }
    }

    service {
      port         = "http"
      address_mode = "host"
      name         = "stirling"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.${NOMAD_JOB_NAME}.entrypoints=https",
        "traefik.http.routers.${NOMAD_JOB_NAME}.tls.certresolver=vault",
      ]

      check {
        type     = "http"
        path     = "/api/v1/info/status"
        interval = "10s"
        timeout  = "2s"
      }
    }
  }
}
