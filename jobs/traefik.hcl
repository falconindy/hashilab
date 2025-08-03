job "traefik" {
  datacenters = ["dc1"]
  type        = "system"

  group "traefik" {
    volume "letsencrypt" {
      type            = "csi"
      read_only       = false
      source          = "letsencrypt"
      access_mode     = "multi-node-multi-writer"
      attachment_mode = "file-system"
    }

    network {
      mode = "bridge"

      port "http" {
        static = 80
      }
      port "https" {
        static = 443
      }
      port "dashboard" {
        static = 9000
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

    task "traefik" {
      driver = "docker"

      volume_mount {
        volume      = "letsencrypt"
        destination = "/letsencrypt"
        read_only   = false
      }

      config {
        image = "traefik:v3.5"
        ports = ["http", "https", "dashboard"]
        volumes = [
          "local/traefik.yml:/etc/traefik/traefik.yml",
        ]
      }

      vault {}

      identity {
        name = "vault_default"
        aud  = ["vault.io"]
        ttl  = "1h"
      }

      template {
        data = <<EOF
entryPoints:
  http:
    address: ":80"
    forwardedHeaders:
      insecure: false
    proxyProtocol:
      insecure: false
      trustedIPs:
        - "172.16.0.0/12"

  https:
    address: ":443"
    forwardedHeaders:
      insecure: false
    proxyProtocol:
      insecure: false
      trustedIPs:
        - "172.16.0.0/12"
    http:
      middlewares:
        - securedheaders@file

  traefik:
    address: ":9000"

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
  insecure: true

providers:
  consulCatalog:
    prefix: "traefik"
    exposedByDefault: false

    endpoint:
      address: "172.17.0.1:8500"
      scheme: "http"

  file:
    filename: "local/static_providers.yml"

certificatesResolvers:
  letsEncrypt:
    acme:
      tlsChallenge: true
      email: "d@falconindy.com"
      storage: "/letsencrypt/acme.{{ env "attr.unique.hostname" }}.json"

  vault:
    acme:
      email: "d@falconindy.com"
      storage: "/letsencrypt/acme.vault.json"
      caServer: "http://172.17.0.1:8200/v1/pki_int/acme/directory"
      httpChallenge:
        entryPoint: "http"

metrics:
  prometheus:
    addEntryPointsLabels: true
    addRoutersLabels: true
    entryPoint: traefik
EOF

        destination = "local/traefik.yml"
      }

      template {
        data        = <<EOF
http:
  routers:
    nasty:
      rule: "Host(`dsm.falconindy.com`)"
      entrypoints: "https"
      tls:
        certresolver: "letsEncrypt"
      service: "nasty"

  services:
    nasty:
      loadBalancer:
        servers:
        - url: "http://nasty.node.home:5000"

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
          X-Backend-Name: {{ env "attr.unique.hostname" }}
EOF
        destination = "local/static_providers.yml"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
