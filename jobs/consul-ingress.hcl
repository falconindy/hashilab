job "consul-ingress" {
  datacenters = ["dc1"]
  type        = "system"

  group "consul-ingress" {

    network {
      mode = "bridge"

      port "http" {
        static = 80
      }

      port "https" {
        static = 443
      }
    }

    service {
      name = "ingress-gateway"

      //meta {
      //  envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}" # make envoy metrics port available in Consul
      //}
      connect {
        gateway {
          ingress {
            listener {
              port     = 80
              protocol = "tcp"

              service {
                name = "caddy-http"
              }
            }

            listener {
              port     = 443
              protocol = "tcp"

              service {
                name = "caddy-https"
              }
            }
          }

          //proxy {
          //  config {
          //    envoy_prometheus_bind_addr = "0.0.0.0:9102"
          //  }
          //}
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
