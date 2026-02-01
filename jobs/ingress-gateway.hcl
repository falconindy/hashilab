job "ingress-gateway" {
  datacenters = ["dc1"]
  type        = "system"

  group "ingress-gateway" {
    network {
      mode = "bridge"

      port "deluge-inbound" { static = 6881 }
      port "external-https" { static = 8443 }

      port "envoy_metrics" { to = 9102 }
    }

    service {
      name = "ingress-gateway"

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}"
      }

      connect {
        gateway {
          proxy {
            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9102"
            }
          }

          ingress {
            listener {
              port     = 8443
              protocol = "tcp"

              service {
                name = "traefik-public"
              }
            }

            listener {
              port     = 6881
              protocol = "tcp"

              service {
                name = "deluge-inbound"
              }
            }
          }
        }

        sidecar_task {
          resources {
            cpu    = 50
            memory = 64
          }
        }
      }
    }
  }
}
