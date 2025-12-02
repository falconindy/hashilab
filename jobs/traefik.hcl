job "traefik" {
  datacenters = ["dc1"]
  type        = "system"

  update {
    max_parallel     = 1
    min_healthy_time = "10s"
    auto_revert      = true
  }

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

  group "traefik" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "http" {
        static = 80
      }
      port "https" {
        static = 443
      }
      port "public" {
        static = 8443
      }
    }

    service {
      name = "traefik"

      check {
        name     = "alive"
        type     = "tcp"
        port     = "https"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "server" {
      driver = "podman"

      config {
        image = "traefik:v3.6"
        ports = ["http", "https", "public"]
        volumes = [
          "/etc/ssl/certs:/etc/ssl/certs:ro",
          "local/traefik.yml:/etc/traefik/traefik.yml:ro",
          "/clusterdata/traefik:/acme:rw",
        ]
      }

      vault {}

      template {
        left_delimiter  = "[["
        right_delimiter = "]]"
        data            = <<-EOF
          entryPoints:
            http:
              address: :[[ env "NOMAD_PORT_http" ]]
              asDefault: false
              forwardedHeaders:
                insecure: false
              proxyProtocol:
                insecure: false
                trustedIPs:
                  - 172.16.0.0/12
              http:
                middlewares:
                  - customheaders@file

            https:
              address: :[[ env "NOMAD_PORT_https" ]]
              asDefault: true
              forwardedHeaders:
                insecure: false
              proxyProtocol:
                insecure: false
                trustedIPs:
                  - 172.16.0.0/12
              http:
                middlewares:
                  - securedheaders@file
                  - customheaders@file
                tls:
                  certresolver: vault

            public:
              address: :[[ env "NOMAD_PORT_public" ]]
              asDefault: false
              forwardedHeaders:
                insecure: false
              proxyProtocol:
                insecure: false
                trustedIPs:
                  - 172.16.0.0/12
              http:
                middlewares:
                  - securedheaders@file
                tls:
                  certresolver: letsEncrypt

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

          providers:
            consulCatalog:
              prefix: traefik
              exposedByDefault: false
              defaultRule: Host(`{{ .Name }}.service.home`)

              endpoint:
                address: 172.17.0.1:8500
                scheme: http

            file:
              filename: local/static_providers.yml

          certificatesResolvers:
            letsEncrypt:
              acme:
                storage: /acme/acme.[[ env "attr.unique.hostname" ]].json
                dnsChallenge:
                  provider: cloudflare
                  delayBeforeCheck: 10

            vault:
              acme:
                email: d@falconindy.com
                storage: /acme/acme.vault.json
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
