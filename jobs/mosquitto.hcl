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

      port "envoy_metrics" { to = 9102 }
    }

    task "server" {
      driver = "docker"
      # Setting this prevents the need for CAP_CHOWN, CAP_SETUID, CAP_SETGID
      user = "1883:1883"

      config {
        image = "eclipse-mosquitto:2.1.2-alpine"

        cap_drop     = ["all"]
        security_opt = ["no-new-privileges=true"]

        volumes = [
          "/clusterdata/mosquitto/config:/mosquitto/config:rw",
          "/clusterdata/mosquitto/data:/mosquitto/data:rw",
          "/clusterdata/mosquitto/log:/mosquitto/log:rw",
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
        sidecar_service {}

        sidecar_task {
          resources {
            cpu    = 50
            memory = 48
          }
        }
      }

      check {
        type    = "script"
        command = "/usr/bin/mosquitto_sub"
        args = [
          "--host", "localhost",
          "--port", "1883",
          "--topic", "$$SYS/#",
          "--id", "consul_probe",
          "--username", "probe",
          "--pw", "probe",
          "-E",
        ]
        interval = "10s"
        task     = "server"
        timeout  = "2s"
      }
    }
  }
}
