job "static-www" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "A high-performance HTTP server serving static content"
    link {
      label = "Upstream"
      url   = "https://nginx.org"
    }
    link {
      label = "GitHub"
      url   = "https://github.com/nginx/nginx"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/_/nginx"
    }
  }

  group "static-www" {
    network {
      mode = "bridge"

      port "envoy_metrics" { to = 9102 }
    }

    task "server" {
      driver = "docker"

      config {
        image = "nginx:1.31.4-alpine"

        cap_add      = ["CHOWN", "DAC_OVERRIDE", "FOWNER", "SETUID", "SETGID"]
        cap_drop     = ["all"]
        security_opt = ["no-new-privileges=true"]

        volumes = [
          "local/nginx.conf:/etc/nginx/conf.d/default.conf",
          "/clusterdata/www:/srv/www:ro",
        ]
      }

      template {
        data        = <<-EOF
          server {
              listen 8080;

              server_name d.service.home;

              location / {
                  root /srv/www/homelabdash;
                  index index.html;
              }
          }
        EOF
        destination = "local/nginx.conf"
        change_mode = "restart"
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }

    service {
      name = "d"
      port = 8080

      tags = [
        "traefik.enable=true",
        "homelabdash.hide",
      ]

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}"
      }

      connect {
        sidecar_service {}

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
        timeout  = "2s"
        expose   = true
      }
    }
  }
}
