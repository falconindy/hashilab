job "deluge" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${attr.unique.network.ip-address}"
    operator  = "="
    value     = "10.0.100.102"
  }

  group "deluge" {
    count = 1

    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "deluge" {
        to = 8112
      }

      port "deluge-inbound" {
        static = 6881
      }
    }

    task "server" {
      driver = "podman"

      config {
        image = "linuxserver/deluge:amd64-2.2.0"
        ports = ["deluge", "deluge-inbound"]
        volumes = [
          "/etc/ssl/certs:/etc/ssl/certs:ro",
          "/clusterdata/media:/media:rw",
          "/clusterdata/deluge:/config:rw",
        ]
      }

      env {
        PUID = 911
        PGID = 911
      }

      resources {
        cpu    = 200
        memory = 1024
      }
    }

    service {
      name         = "deluge"
      port         = "deluge"
      address_mode = "host"

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "5s"
      }
    }
  }
}
