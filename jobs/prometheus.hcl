job "prometheus" {
  datacenters = ["dc1"]
  type        = "service"

  group "monitoring" {
    count = 1

    network {
      mode = "host"

      dns {
        servers = ["172.17.0.1"]
      }

      port "http" {}

      port "blackbox" {}
    }

    volume "prometheus" {
      type            = "csi"
      read_only       = false
      source          = "prometheus"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    task "blackbox-exporter" {
      driver = "podman"

      config {
        image = "prom/blackbox-exporter:v0.27.0"
        args = [
          "--web.listen-address", "${NOMAD_ADDR_blackbox}",
          "--config.file", "local/blackbox.yml",
        ]
        # needed in order to bind to NOMAD_ADDR_http
        network_mode = "host"
        ports        = ["blackbox"]
        volumes = [
          "/etc/ssl/certs:/etc/ssl/certs:ro"
        ]
      }

      template {
        data = <<EOH
modules:
  http_2xx:
    prober: http
    http:
      preferred_ip_protocol: "ip4"
  consul_http_2xx:
    prober: http
    http:
      preferred_ip_protocol: "ip4"
      tls_config:
        server_name: consul.service.home
  vault_http_2xx:
    prober: http
    http:
      preferred_ip_protocol: "ip4"
      tls_config:
        server_name: vault.service.home
  http_post_2xx:
    prober: http
    http:
      method: POST
  tcp_connect:
    prober: tcp
  pop3s_banner:
    prober: tcp
    tcp:
      query_response:
      - expect: "^+OK"
      tls: true
      tls_config:
        insecure_skip_verify: false
  grpc:
    prober: grpc
    grpc:
      tls: true
      preferred_ip_protocol: "ip4"
  grpc_plain:
    prober: grpc
    grpc:
      tls: false
      service: "service1"
  ssh_banner:
    prober: tcp
    tcp:
      query_response:
      - expect: "^SSH-2.0-"
      - send: "SSH-2.0-blackbox-ssh-check"
  irc_banner:
    prober: tcp
    tcp:
      query_response:
      - send: "NICK prober"
      - send: "USER prober prober prober :prober"
      - expect: "PING :([^ ]+)"
        send: "PONG ${1}"
      - expect: "^:[^ ]+ 001"
  icmp:
    prober: icmp
  icmp_ttl5:
    prober: icmp
    timeout: 5s
    icmp:
      ttl: 5
EOH
        destination   = "local/blackbox.yml"
      }
    }

    task "prometheus" {
      driver = "podman"
      user   = "1000:2000"

      vault {}

      identity {
        name = "vault_default"
        aud  = ["vault.io"]
        ttl  = "1h"
      }

      volume_mount {
        volume      = "prometheus"
        destination = "/opt/prometheus"
        read_only   = false
      }

      service {
        name         = "prometheus"
        port         = "http"
        address_mode = "host"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.${NOMAD_JOB_NAME}.entrypoints=http",
          "traefik.http.routers.${NOMAD_JOB_NAME}-https.entrypoints=https",
          "traefik.http.routers.${NOMAD_JOB_NAME}-https.tls.certresolver=vault",
        ]

        check {
          type     = "http"
          path     = "/-/healthy"
          name     = "http"
          interval = "5s"
          timeout  = "2s"
        }
      }

      # main configuration file
      template {
        data = <<EOH
global:
  scrape_interval:     15s # Set the scrape interval to every 15 seconds. Default is every 1 minute.
  evaluation_interval: 15s # Evaluate rules every 15 seconds. The default is every 1 minute.
  # scrape_timeout is set to the global default (10s).

scrape_configs:
  - job_name: 'nomad'
    consul_sd_configs:
    - server: '{{ env "NOMAD_IP_http" }}:8500'
      services: ['nomad-client']
      scheme: http
    metrics_path: /v1/metrics
    params:
      format: ['prometheus']
    relabel_configs:
      - source_labels: ['__meta_consul_dc']
        target_label:  'dc'
      - source_labels: [__meta_consul_service]
        target_label:  'job'
      - source_labels: ['__meta_consul_node']
        target_label:  'host'

  - job_name: 'tls-expiration-check'
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
        - https://omada-controller.service.home:8043
    # A relabeling config that lets us scrape target through the Blackbox Exporter,
    # while labeling the resulting metrics with the probed target's URL.
    relabel_configs:
      # Set the "target" HTTP parameter to the target URL that we want to probe.
      - source_labels: [__address__]
        target_label: __param_target
      # Set the "instance" label to the target URL that we want to probe.
      - source_labels: [__param_target]
        target_label: instance
      # Don't actually scrape the target itself, but the Blackbox Exporter.
      - target_label: __address__
        replacement: {{ env "NOMAD_ADDR_blackbox" }}

  - job_name: 'consul-tls-expiration-check'
    metrics_path: /probe
    params:
      module: [consul_http_2xx]
    static_configs:
      - targets:
        - https://nomad0.node.home:8501
        - https://nomad1.node.home:8501
        - https://nomad2.node.home:8501
        - https://bastion.node.home:8501
        - https://nasty.node.home:8501
    # A relabeling config that lets us scrape target through the Blackbox Exporter,
    # while labeling the resulting metrics with the probed target's URL.
    relabel_configs:
      # Set the "target" HTTP parameter to the target URL that we want to probe.
      - source_labels: [__address__]
        target_label: __param_target
      # Set the "instance" label to the target URL that we want to probe.
      - source_labels: [__param_target]
        target_label: instance
      # Don't actually scrape the target itself, but the Blackbox Exporter.
      - target_label: __address__
        replacement: {{ env "NOMAD_ADDR_blackbox" }}

  - job_name: 'vault-tls-expiration-check'
    metrics_path: /probe
    params:
      module: [vault_http_2xx]
    static_configs:
      - targets:
        - https://nomad0.node.home:8200
        - https://nomad1.node.home:8200
        - https://nomad2.node.home:8200
    # A relabeling config that lets us scrape target through the Blackbox Exporter,
    # while labeling the resulting metrics with the probed target's URL.
    relabel_configs:
      # Set the "target" HTTP parameter to the target URL that we want to probe.
      - source_labels: [__address__]
        target_label: __param_target
      # Set the "instance" label to the target URL that we want to probe.
      - source_labels: [__param_target]
        target_label: instance
      # Don't actually scrape the target itself, but the Blackbox Exporter.
      - target_label: __address__
        replacement: {{ env "NOMAD_ADDR_blackbox" }}

  - job_name: 'consul-server'
    metrics_path: /v1/agent/metrics
    honor_labels: true
    consul_sd_configs:
      - server: '{{ env "NOMAD_IP_http" }}:8500'
        services: ['nomad-client']
        scheme: http
    relabel_configs:
      - source_labels: ['__meta_consul_dc']
        target_label:  'dc'
      - source_labels: ['__meta_consul_node']
        target_label:  'host'
      - source_labels: ['__meta_consul_tags']
        target_label: 'tags'
      - source_labels: [__address__]
        action: replace
        regex: ([^:]+):.*
        replacement: $1:8500
        target_label: __address__

  - job_name: 'vault'
    metrics_path: /v1/sys/metrics
    scheme: https
    bearer_token: "hvs.CAESIHNY8eep34yYRMgjDT2w5ZCH_YistlXlMLv4hEpWvXlmGh4KHGh2cy5Vb3dWT0lwdTZaZGhwaEphUTZHeWFMcVI"
    params:
      format: ['prometheus']
    tls_config:
      insecure_skip_verify: true
    consul_sd_configs:
      - server: {{ env "NOMAD_IP_http" }}:8500
        services: ['vault']
    relabel_configs:
      - source_labels: ['__meta_consul_dc']
        target_label:  'dc'
      - source_labels: ['__meta_consul_node']
        target_label:  'host'

  - job_name: 'traefik'
    metrics_path: /metrics
    consul_sd_configs:
      - server: '{{ env "NOMAD_IP_http" }}:8500'
        services: ['traefik']
        scheme: http
    relabel_configs:
      - source_labels: ['__meta_consul_dc']
        target_label:  'dc'
      - source_labels: ['__meta_consul_node']
        target_label:  'host'
      - source_labels: [__address__]
        action: replace
        regex: ([^:]+):.*
        replacement: $1:9000
        target_label: __address__

  - job_name: 'coredns'
    metrics_path: /metrics
    scheme: http
    consul_sd_configs:
      - server: '{{ env "NOMAD_IP_http" }}:8500'
        services: ['coredns']
        scheme: http
    relabel_configs:
      - source_labels: ['__meta_consul_dc']
        target_label:  'dc'
      - source_labels: ['__meta_consul_node']
        target_label:  'host'
      - source_labels: [__address__]
        action: replace
        regex: ([^:]+):.*
        replacement: $1:9153
        target_label: __address__

  - job_name: 'omada'
    metrics_path: /metrics
    scheme: http
    scrape_interval: 30s
    scrape_timeout: 25s
    consul_sd_configs:
      - server: '{{ env "NOMAD_IP_http" }}:8500'
        services: ['omada-exporter']
        scheme: http
    relabel_configs:
      - source_labels: ['__meta_consul_dc']
        target_label:  'dc'
      - source_labels: ['__meta_consul_node']
        target_label:  'host'

EOH

        destination   = "local/prometheus.yml"
        change_mode   = "signal"
        change_signal = "SIGHUP"
        env           = false
      }

      config {
        image = "prom/prometheus:v3.6.0"
        args = [
          "--storage.tsdb.path", "/opt/prometheus",
          "--web.listen-address", "${NOMAD_ADDR_http}",
          "--storage.tsdb.retention.time", "900d"
        ]
        # needed in order to bind to NOMAD_ADDR_http
        network_mode = "host"
        ports        = ["http"]
        volumes = [
          "local/prometheus.yml:/prometheus/prometheus.yml",
          "/etc/ssl/certs:/etc/ssl/certs:ro"
        ]
      }

      resources {
        cpu    = 100
        memory = 256
      }
    }
  }
}
