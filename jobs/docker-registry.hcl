job "docker-registry" {
  datacenters = ["dc1"]
  type        = "service"

  group "docker-registry" {
    count = 1

    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "http" {
        to = 5000
      }
    }

    task "server" {
      driver = "podman"

      config {
        image = "registry:2"
        volumes = [
          "local/config.yml:/etc/docker/registry/config.yml:ro",
          "/clusterdata/docker-registry:/var/lib/registry:rw",
        ]
      }

      service {
        name         = "docker-registry"
        port         = "http"
        address_mode = "host"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.${NOMAD_JOB_NAME}.entrypoints=https",
          "traefik.http.routers.${NOMAD_JOB_NAME}.tls.certresolver=vault",
        ]
      }

      resources {
        cpu    = 100
        memory = 512
      }

      template {
        data          = <<EOF
          version: 0.1
          http:
            addr: {{ env "NOMAD_ALLOC_ADDR_http" }}
            host: https://{{ env "NOMAD_JOB_NAME" }}.service.home
          log:
            fields:
              service: registry
          storage:
            cache:
              blobdescriptor: inmemory
            filesystem:
              rootdirectory: /var/lib/registry
          proxy:
            remoteurl: https://registry-1.docker.io
            ttl: 168h
        EOF
        destination   = "local/config.yml"
        change_mode   = "signal"
        change_signal = "SIGHUP"
        env           = false
      }
    }
  }
}
