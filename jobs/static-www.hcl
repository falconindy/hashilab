job "static-www" {
  datacenters = ["dc1"]

  group "static-www" {
    network {
      mode = "bridge"

      port "http" {
        to = 80
      }
    }

    volume "www" {
      type            = "csi"
      read_only       = true
      source          = "www"
      access_mode     = "single-node-reader-only"
      attachment_mode = "file-system"
    }

    task "server" {
      driver = "podman"
      config {
        image = "nginx"
        ports = ["http"]
        network_mode = "host"
        volumes = [
          "local/nginx.conf:/etc/nginx/conf.d/default.conf"
        ]

      }

      template {
        data = <<EOF
        server {
            listen {{ env "NOMAD_PORT_http" }};

            server_name d.service.home;

            location / {
                root /srv/traefik-directory;
                index index.html;
            }
        }
        EOF
        destination = "local/nginx.conf"
        change_mode = "restart"
      }


      volume_mount {
        volume = "www"
        destination = "/srv"
        read_only = true
      }
    }

    service {
      name = "d"
      port = "http"
      address_mode = "host"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.d.entrypoints=http",
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
