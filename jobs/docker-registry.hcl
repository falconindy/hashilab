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

  # Read-write registry for our own images. This is the one you `docker push` to
  # at docker-registry.service.home. It has no `proxy` block, because enabling
  # pull-through cache mode makes a registry read-only (rejects pushes).
  group "private" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "envoy_metrics" { to = 9102 }
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
            addr: 0.0.0.0:5000
            host: https://docker-registry.service.home
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
        EOF
        destination   = "local/config.yml"
        change_mode   = "signal"
        change_signal = "SIGHUP"
        env           = false
      }
    }

    service {
      name = "docker-registry"
      port = 5000

      tags = [
        "traefik.enable=true",
        "homelabdash.uri=/v2/_catalog",
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

            expose {
              path {
                path            = "/metrics"
                protocol        = "http"
                local_path_port = 9102
                listener_port   = "envoy_metrics"
              }
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
        path     = "/v2/_catalog"
        interval = "10s"
        timeout  = "2s"
        expose   = true
      }
    }
  }

  # Pull-through cache (mirror) for docker.io. Docker daemons point their
  # `registry-mirrors` at docker-registry-cache.service.home (see
  # os/etc/docker/daemon.json) so docker.io pulls are cached locally. A registry
  # in proxy mode is read-only — do NOT push to this one.
  group "cache" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "envoy_metrics" { to = 9102 }
    }

    task "server" {
      driver = "docker"

      config {
        image = "registry:3.1.1"
        volumes = [
          "local/config.yml:/etc/distribution/config.yml:ro",
          "/clusterdata/docker-registry-cache:/var/lib/registry:rw",
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
            addr: 0.0.0.0:5000
            host: https://docker-registry-cache.service.home
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
      name = "docker-registry-cache"
      port = 5000

      tags = [
        "traefik.enable=true",
        "homelabdash.uri=/v2/_catalog",
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

            expose {
              path {
                path            = "/metrics"
                protocol        = "http"
                local_path_port = 9102
                listener_port   = "envoy_metrics"
              }
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
        path     = "/v2/_catalog"
        interval = "10s"
        timeout  = "2s"
        expose   = true
      }
    }
  }
}
