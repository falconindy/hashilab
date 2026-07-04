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

      port "envoy_metrics" { to = 9102 }
    }

    ephemeral_disk {
      size    = 300 # MB
      migrate = true
    }

    service {
      name = "traefik"
      port = "https"

      tags = [
        "traefik.enable=true",
        "homelabdash.uri=/dashboard/",
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
      driver = "docker"

      config {
        image = "traefik:v3.7.6"
        volumes = [
          "local/traefik.yml:/etc/traefik/traefik.yml:ro",
        ]
      }

      vault {}

      template {
        data        = <<-EOF
          {{- with secret "pki_int/cert/ca_chain" }}
            {{- .Data.ca_chain }}
          {{ end }}
        EOF
        destination = "local/home.pem"
      }

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
                  - 10.0.1.0/24
                  - 10.0.100.0/24
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

          accessLog:
            format: json
            fields:
              names:
                StartUTC: drop

          providers:
            consulCatalog:
              prefix: traefik
              connectaware: true
              watch: true
              exposedByDefault: false
              servicename: traefik
              defaultRule: Host(`{{ .Name }}.service.home`)

              endpoint:
                address: consul.service.home:8501
                scheme: https
                tls:
                  ca: [[ env "NOMAD_TASK_DIR" ]]/home.pem

            file:
              filename: local/static_providers.yml

          certificatesResolvers:
            vault:
              acme:
                email: d@falconindy.com
                storage: [[ env "NOMAD_ALLOC_DIR" ]]/data/acme.vault.json
                caCertificates:
                  - [[ env "NOMAD_TASK_DIR" ]]/home.pem
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

      env {
        TZ = "America/New_York"
      }

      resources {
        cpu    = 500
        memory = 128
      }
    }
  }
}
