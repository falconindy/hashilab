job "traefik" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "A modern HTTP reverse proxy and load balancer"
    link {
      label = "Upstream"
      url   = "https://traefik.io"
    }
    link {
      label = "GitHub"
      url   = "https://github.com/traefik/traefik"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/_/traefik"
    }
  }

  update {
    max_parallel     = 1
    min_healthy_time = "10s"
    auto_revert      = true
  }

  group "traefik" {
    count = 2

    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "http" { static = 80 }
      port "https" { static = 443 }

      port "envoy_metrics_http" { to = 9102 }
      port "envoy_metrics_https" { to = 9103 }
    }

    ephemeral_disk {
      size    = 300 # MB
      migrate = true
    }

    service {
      name         = "traefik-insecure"
      port         = "http"
      address_mode = "host"

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics_http}"
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
        type     = "http"
        path     = "/ping"
        interval = "5s"
        timeout  = "2s"
        expose   = true
      }
    }

    service {
      name         = "traefik"
      port         = "https"
      address_mode = "host"

      tags = [
        "traefik.enable=true",
      ]

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics_https}"
      }

      connect {
        sidecar_service {
          proxy {
            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9103"
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
    }

    task "server" {
      driver = "podman"

      config {
        image = "traefik:v3.6.7"
        volumes = [
          "/etc/ssl/certs:/etc/ssl/certs:ro",
          "local/traefik.yml:/etc/traefik/traefik.yml:ro",
        ]
      }

      vault {}

      template {
        left_delimiter  = "[["
        right_delimiter = "]]"
        data            = <<-EOF
          entryPoints:
            http:
              address: :80
              asDefault: false
              forwardedHeaders:
                insecure: false
              proxyProtocol:
                insecure: false
                trustedIPs: &trustedIPs
                  - 172.16.0.0/12
                  - 172.26.64.0/20
                  - 127.0.0.1/32
              http:
                middlewares:
                  - internal-only@file
                  - customheaders@file

            https:
              address: :443
              asDefault: true
              forwardedHeaders:
                insecure: false
              proxyProtocol:
                insecure: false
                trustedIPs: *trustedIPs
              http:
                middlewares:
                  - internal-only@file
                  - securedheaders@file
                  - customheaders@file
                tls:
                  certresolver: vault

          tls:
            options:
              default:
                sniStrict: true
                minVersion: VersionTLS12
                curvePreferences:
                  - CurveP521
                  - CurveP384
                cipherSuites:
                  - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
                  - TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
                  - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
                  - TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305
                  - TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305
              mintls13:
                minVersion: VersionTLS13

          api:
            dashboard: true
            insecure: false

          ping:
            entrypoint: http

          log:
            level: INFO

          accessLog: {}

          providers:
            consulCatalog:
              prefix: traefik
              connectaware: true
              watch: true
              exposedByDefault: false
              servicename: traefik
              defaultRule: Host(`{{ .Name }}.service.home`)

              endpoint:
                address: 172.17.0.1:8500
                scheme: http

            file:
              filename: local/static_providers.yml

          certificatesResolvers:
            vault:
              acme:
                email: d@falconindy.com
                storage: [[ env "NOMAD_ALLOC_DIR" ]]/data/acme.vault.json
                caServer: https://vault.service.home:8200/v1/pki_int/acme/directory
                httpChallenge:
                  entryPoint: http

          metrics:
            prometheus:
              addEntryPointsLabels: true
              addRoutersLabels: true
              entryPoint: https
        EOF
        destination     = "local/traefik.yml"
      }

      template {
        left_delimiter  = "[["
        right_delimiter = "]]"
        data            = <<-EOF
          http:
            routers:
              api-dashboard:
                rule: Host(`traefik.service.home`) && (PathPrefix(`/api`) || PathPrefix(`/dashboard`))
                entrypoints: https
                service: api@internal
                middlewares:
                  - cors-allow-all

            middlewares:
              securedheaders:
                headers:
                  forcestsheader: true
                  sslRedirect: true
                  STSPreload: true
                  ContentTypeNosniff: true
                  BrowserXssFilter: true
                  STSIncludeSubdomains: true
                  STSSeconds: 315360000

              customheaders:
                headers:
                  customResponseHeaders:
                    X-Backend-Name: [[ env "attr.unique.hostname" ]]

              cors-allow-all:
                headers:
                  accessControlAllowOriginList: ["*"]
                  accessControlAllowMethods:
                    - GET
                  accessControlAllowHeaders:
                    - Content-Type
                    - Authorization
                  accessControlAllowCredentials: true
                  accessControlMaxAge: 100
                  addVaryHeader: true

              internal-only:
                ipAllowList:
                  sourceRange:
                    - 127.0.0.1/32
                    - 172.26.64.0/20
                    - 10.0.1.0/24
                    - 10.0.20.0/24
                    - 10.0.100.0/24
        EOF
        destination     = "local/static_providers.yml"
      }

      template {
        data        = <<EOF
          CF_API_EMAIL="d@falconindy.com"
          {{ with secret "kv/data/default/traefik" }}
            CF_DNS_API_TOKEN="{{ .Data.data.cloudflare_api_token }}"
          {{ end }}
        EOF
        destination = "secrets/cloudflare.env"
        env         = true
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
