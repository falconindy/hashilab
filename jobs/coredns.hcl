job "coredns" {
  datacenters = ["dc1"]
  type        = "system"

  update {
    max_parallel     = 1
    min_healthy_time = "10s"
    auto_revert      = true
  }

  ui {
    description = "A plugin-driven DNS server/forwarder"
    link {
      label = "Upstream"
      url   = "https://coredns.io"
    }
    link {
      label = "GitHub"
      url   = "https://github.com/coredns/coredns"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/r/coredns/coredns"
    }
  }

  group "coredns" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "dns" {
        static = 53
      }

      port "metrics" {}
      port "health" {}
    }

    task "server" {
      driver = "docker"

      config {
        image = "coredns/coredns:1.14.7"
        ports = ["dns", "metrics", "health"]

        cap_add      = ["NET_BIND_SERVICE"]
        cap_drop     = ["all"]
        security_opt = ["no-new-privileges=true"]

        args = ["-conf", "/local/corefile"]
      }

      # An explicit consul identity is needed to render the config.
      consul {}

      template {
        # render with: consul-template -once -dry -template jobs/coredns.hcl
        data          = <<-EOF
          (default) {
            errors
            prometheus :{$NOMAD_PORT_metrics}
          }

          . {
            {{- with service "adguard-dns" }}
            forward . {{ range . }}{{ .Address }}:{{ .Port }} {{ end }}{
              policy round_robin
              health_check 5s
            }
            {{- else }}
            forward . 1.1.1.1 8.8.8.8
            {{- end }}

            cache {
              success 1000
              prefetch 5 10m
              serve_stale 1h immediate
            }

            health :{$NOMAD_PORT_health}

            import default
          }

          home.:53 consul.:53 {
            {{- /* load balance requests to traefik instances if possible */}}
            {{- range $tag, $services := services | byTag -}}
              {{- if eq $tag "traefik.enable=true" }}{{- range $services }}
                {{- if not (.Name | sprig_hasSuffix "-sidecar-proxy") }}
            rewrite name exact {{ .Name }}.service.home traefik.service.home
                {{- end }}
              {{- end }}{{ end }}
            {{- end }}

            forward . {$NOMAD_HOST_IP_dns}:8600

            header {
              response set ra # set RecursionAvailable flag
            }

            import default
          }
        EOF
        destination   = "local/corefile"
        change_mode   = "signal"
        change_signal = "SIGUSR1"
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }

    service {
      name = "coredns"
      port = "health"

      meta {
        coredns_metrics_port = "${NOMAD_HOST_PORT_metrics}"
      }

      check {
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "2s"
      }
    }
  }
}
