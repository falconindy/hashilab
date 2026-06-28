job "docker-registry" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "A stateless, highly scalable server for storing and distributing container images"
    link {
      label = "Upstream"
      url   = "https://distribution.github.io/distribution/"
    }
    link {
      label = "GitHub"
      url   = "https://github.com/distribution/distribution"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/_/registry"
    }
  }

  group "docker-registry" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "http" {}
    }

    task "server" {
      driver = "docker"

      config {
        image = "registry:3.1.1"
        volumes = [
          "local/config.yml:/etc/distribution/config.yml:ro",
          "/clusterdata/docker-registry:/var/lib/registry:rw",
        ]
      }

      resources {
        cpu    = 100
        memory = 512
      }

      env {
        # No OTLP collector here.
        OTEL_TRACES_EXPORTER = "none"
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
            level: info
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
