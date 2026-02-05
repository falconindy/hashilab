job "static-www" {
  datacenters = ["dc1"]
  type        = "service"

  group "static-www" {
    network {
      mode = "bridge"

      port "envoy_metrics" { to = 9102 }
    }

    task "server" {
      driver = "podman"

      config {
        image = "nginx"
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
        "traefik.consulcatalog.connect=true",
        "homelabdash.hide",
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
