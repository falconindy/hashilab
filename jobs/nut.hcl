job "nut" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${meta.has_ups}"
    operator  = "="
    value     = "true"
  }

  group "nut" {
    count = 1

    network {
      port "nut" {
        static = 3493
      }
    }

    task "nut" {
      driver = "docker"

      config {
        image = "instantlinux/nut-upsd:2.8.2-r2"
        ports = ["nut"]

        devices = [
          {
            host_path          = "/dev/bus/usb"
            container_path     = "/dev/bus/usb"
            cgroup_permissions = "rw"
          }
        ]
      }

      env {
        API_PASSWORD = "11111"
      }

      service {
        name = "nut"
        port = "nut"

        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "5s"
        }
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
