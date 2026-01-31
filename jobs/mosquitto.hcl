job "mosquitto" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "A message broker that implements the MQTT protocol"
    link {
      label = "Upstream"
      url   = "https://mosquitto.org"
    }
    link {
      label = "GitHub"
      url   = "https://github.com/eclipse-mosquitto/mosquitto"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/_/eclipse-mosquitto"
    }
  }

  group "mosquitto" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "envoy_metrics" { to = 9102 }
    }

    task "server" {
      driver = "podman"
      config {
        image = "eclipse-mosquitto:2.0.22"

        volumes = [
          "/clusterdata/mosquitto:/mosquitto:rw",
        ]
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }

    service {
      name = "mosquitto"
      port = 1883

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
        type     = "script"
        command  = "/usr/bin/mosquitto_sub"
        args     = ["-h", "localhost", "-p", "1883", "-t", "$$SYS/#", "-E", "-i", "probe"]
        interval = "10s"
        task     = "server"
        timeout  = "2s"
      }
    }
  }
}
