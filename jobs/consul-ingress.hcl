job "consul-ingress" {
  datacenters = ["dc1"]
  type        = "system"

  group "consul-ingress" {
    network {
      mode = "bridge"

      port "http" { static = 80 }
      port "https" { static = 443 }
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
              port     = 80
              protocol = "tcp"

              service {
                name = "traefik-insecure"
              }
            }

            listener {
              port     = 443
              protocol = "tcp"

              service {
                name = "traefik"
              }
            }

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
            cpu    = 100
            memory = 128
          }
        }
      }
    }
  }
}
