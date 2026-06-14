job "docker-registry" {
  datacenters = ["dc1"]
  type        = "service"

  group "docker-registry" {
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
      driver = "docker"

      config {
        image = "registry:3"
        volumes = [
          "local/config.yml:/etc/docker/registry/config.yml:ro",
          "/clusterdata/docker-registry:/var/lib/registry:rw",
        ]
      }

      resources {
        cpu    = 100
        memory = 512
      }

      template {
        data          = <<-EOF
          version: 0.1
          http:
            addr: {{ env "NOMAD_ALLOC_ADDR_http" }}
            host: https://{{ env "NOMAD_JOB_NAME" }}.service.home
            headers:
              X-Content-Type-Option: [nosniff]
          log:
            fields:
              service: registry
          storage:
            cache:
              blobdescriptor: inmemory
            filesystem:
              rootdirectory: /var/lib/registry
            delete:
              enabled: true
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

    service {
      name = "docker-registry"
      port = "http"

      tags = [
        "traefik.enable=true",
      ]

      check {
        type     = "http"
        path     = "/v2/_catalog"
        interval = "10s"
        timeout  = "2s"
      }
    }
  }
}
