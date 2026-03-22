job "traefik-ingress" {
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

  group "traefik-ingress" {
    count = 2

    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "https" { static = 8443 }
      port "webrtc" { static = 58555 }
      port "deluge" { static = 52520 }

      port "envoy_metrics" { to = 9102 }
    }

    ephemeral_disk {
      size    = 300 # MB
      migrate = true
    }

    service {
      name = "traefik-ingress"
      port = 8080

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}"
      }

      # Expose the dashboard on the internal traefik instance.
      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=true",

        "homelabdash.uri=/dashboard/",
      ]

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
        image = "traefik:v3.6.10"
        volumes = [
          "/etc/ssl/certs:/etc/ssl/certs:ro",
          "local/traefik.yml:/etc/traefik/traefik.yml:ro",
          "/clusterdata/traefik/plugins/geoblock-0.3.7:/plugins-local/src/github.com/PascalMinder/geoblock:ro",
        ]
      }

      vault {}

      template {
        left_delimiter  = "[["
        right_delimiter = "]]"
        data            = <<-EOF
          entryPoints:
            dashboard:
              address: :8080
              asDefault: false
              http:
                middlewares:
                  - internal-only@file

            https:
              address: :[[ env "NOMAD_HOST_PORT_https" ]]
              asDefault: true
              forwardedHeaders:
                insecure: false
              http:
                middlewares:
                  - securedheaders@file
                  - geoblock-us@file
                tls:
                  certresolver: letsencrypt

            deluge:
              address: :[[ env "NOMAD_HOST_PORT_deluge" ]]
              asDefault: false

            webrtc:
              address: :[[ env "NOMAD_HOST_PORT_webrtc" ]]/udp
              asDefault: false

          tls:
            stores:
              default:
                defaultGeneratedCert:
                  resolver: letsencrypt
                  domain:
                    main: falconindy.com
                    sans:
                      - "*.falconindy.com"
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
            entrypoint: https
            manualRouting: true

          log:
            level: INFO

          accessLog:
            fields:
              names:
                StartUTC: drop

          providers:
            consulCatalog:
              prefix: traefik-ingress
              connectaware: true
              watch: true
              exposedByDefault: false
              servicename: traefik-ingress
              defaultRule: Host(`{{ .Name }}.falconindy.com`)

              endpoint:
                address: 172.17.0.1:8500
                scheme: http

            file:
              filename: local/static_providers.yml

          certificatesResolvers:
            letsencrypt:
              acme:
                storage: [[ env "NOMAD_ALLOC_DIR" ]]/data/acme.letsencrypt.json
                dnsChallenge:
                  provider: cloudflare
                  delayBeforeCheck: 10

          experimental:
            localPlugins:
              geoblock:
                moduleName: github.com/PascalMinder/geoblock
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
                rule: (PathPrefix(`/api`) || PathPrefix(`/dashboard`))
                entrypoints: dashboard
                service: api@internal

              home-ca-cert:
                rule: Host(`scoot.falconindy.com`) && Path(`/home.pem`)
                service: vault-service-home
                middlewares:
                  - vault-pem-path
                  - cert-download-headers

              ping:
                rule: Host(`localhost`) && PathPrefix(`/ping`)
                service: ping@internal

            services:
              vault-service-home:
                loadBalancer:
                  servers:
                    - url: https://vault.service.home:8200

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

              internal-only:
                ipAllowList:
                  sourceRange:
                    - 127.0.0.1/32
                    - 172.26.64.0/20
                    - 10.0.1.0/24
                    - 10.0.20.0/24
                    - 10.0.100.0/24

              vault-pem-path:
                replacePath:
                  path: /v1/pki/ca/pem

              cert-download-headers:
                headers:
                  customResponseHeaders:
                    Content-Type: "application/x-x509-ca-cert"
                    Content-Disposition: "attachment; filename=home.pem"
                    X-Frame-Options: "DENY"

              geoblock-us:
                plugin:
                  geoblock:
                    allowLocalRequests: true
                    logLocalRequests: false
                    logAllowedRequests: false
                    logApiRequests: true
                    api: "https://get.geojs.io/v1/ip/country/{ip}"
                    apiTimeoutMs: 750
                    cacheSize: 15
                    forceMonthlyUpdate: true
                    allowUnknownCountries: false
                    unknownCountryApiResponse: nil
                    countries:
                      - US
        EOF
        destination     = "local/static_providers.yml"
      }

      template {
        data        = <<EOF
          CF_API_EMAIL="d@falconindy.com"
          {{ with secret "kv/data/default/traefik-ingress" }}
            CF_DNS_API_TOKEN="{{ .Data.data.cloudflare_api_token }}"
          {{ end }}
        EOF
        destination = "secrets/cloudflare.env"
        env         = true
      }

      env {
        TZ = "America/New_York"
      }

      resources {
        cpu    = 200
        memory = 128
      }
    }
  }
}
