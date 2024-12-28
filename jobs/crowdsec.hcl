job "crowdsec" {
  datacenters = ["dc1"]
  type        = "service"

  group "crowdsec" {
    volume "crowdsec-db" {
      type            = "csi"
      read_only       = false
      source          = "crowdsec-db"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    volume "crowdsec-etc" {
      type            = "csi"
      read_only       = false
      source          = "crowdsec-etc"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    volume "crowdsec-logs" {
      type            = "csi"
      read_only       = false
      source          = "crowdsec-logs"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    volume "traefik-logs" {
      type      = "csi"
      read_only = true
      source    = "traefik"
      # Doesn't actually need to be writeable but Nomad doesn't support us
      # mounting this volume as read-only for crowdsec and read-write for
      # traefik.
      access_mode     = "multi-node-multi-writer"
      attachment_mode = "file-system"
    }

    network {
      mode = "bridge"

      port "lapi" {
        static = 8080
      }
    }

    service {
      name = "crowdsec"

      check {
        name     = "alive"
        type     = "tcp"
        port     = "lapi"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "crowdsec" {
      driver = "docker"

      config {
        image = "crowdsecurity/crowdsec:v1.6.4"
      }

      volume_mount {
        volume      = "crowdsec-logs"
        destination = "/var/log/crowdsec"
      }
      volume_mount {
        volume      = "crowdsec-db"
        destination = "/var/lib/crowdsec/data"
      }
      volume_mount {
        volume      = "crowdsec-etc"
        destination = "/etc/crowdsec"
      }
      volume_mount {
        volume      = "traefik-logs"
        destination = "/logs/traefik"
      }

      resources {
        cpu    = 100
        memory = 512
      }

      env {
        COLLECTIONS = "crowdsecurity/traefik crowdsecurity/http-cve"
        PGID        = "1000"
      }
    }
  }
}

variable crowdseclapikey {
  type = string
}
