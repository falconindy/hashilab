job "static-www" {
  datacenters = ["dc1"]

  group "static-www" {
    network {
      mode = "bridge"

      port "http" {
        to = 80
      }
    }

    task "server" {
      driver = "podman"
      config {
        image        = "nginx"
        ports        = ["http"]
        network_mode = "host"
        volumes = [
          "local/nginx.conf:/etc/nginx/conf.d/default.conf",
          "/clusterdata/www:/srv/www:ro",
        ]

      }

      template {
        data        = <<EOF
        server {
            listen {{ env "NOMAD_PORT_http" }};

            server_name d.service.home;

            location / {
                root /srv/www/traefik-directory;
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
      name         = "d"
      port         = "http"
      address_mode = "host"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.d.entrypoints=https",
      ]

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }
    }
  }
}
