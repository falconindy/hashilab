job "prometheus" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "Monitoring system and time series database"
    link {
      label = "Upstream"
      url   = "https://prometheus.io"
    }
    link {
      label = "GitHub"
      url   = "https://github.com/prometheus/prometheus"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/r/prom/prometheus"
    }
  }

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
          "/etc/ssl/certs:/etc/ssl/certs:ro",
        ]
      }

      resources {
        cpu    = 100
        memory = 128
      }

      template {
        data        = <<EOH
modules:
  http_2xx:
    prober: http
    http:
      preferred_ip_protocol: "ip4"
EOH
        destination = "local/blackbox.yml"
      }
    }

    task "prometheus" {
      driver = "podman"
      user   = "1000:2000"

      vault {}

      service {
        name         = "prometheus"
        port         = "http"
        address_mode = "host"
        tags = [
          "traefik.enable=true",
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
  - job_name: nomad
    scheme: https
    consul_sd_configs:
      - server: consul.service.home:8501
        scheme: https
        services: [nomad-client]
    metrics_path: /v1/metrics
    params:
      format: [prometheus]
    relabel_configs:
      - source_labels: [__meta_consul_dc]
        target_label:  dc
      - source_labels: [__meta_consul_service]
        target_label:  job
      - source_labels: [__meta_consul_node]
        target_label:  host

  - job_name: consul
    metrics_path: /v1/agent/metrics
    params:
      format: [prometheus]
    honor_labels: true
    scheme: https
    tls_config:
      server_name: consul.service.home
    consul_sd_configs:
      - server: consul.service.home:8501
        scheme: https
        services: [consul]
    relabel_configs:
      - source_labels: [__meta_consul_dc]
        target_label:  dc
      - source_labels: [__meta_consul_node]
        target_label:  host
      - source_labels: [__meta_consul_tags]
        target_label: tags
      - source_labels: [__address__]
        action: replace
        regex: ([^:]+):.*
        replacement: $1:8501
        target_label: __address__

  - job_name: vault
    metrics_path: /v1/sys/metrics
    scheme: https
    bearer_token: {{ env "VAULT_TOKEN" }}
    params:
      format: [prometheus]
    consul_sd_configs:
      - server: consul.service.home:8501
        scheme: https
        services: [vault]
    relabel_configs:
      - source_labels: [__meta_consul_dc]
        target_label:  dc
      - source_labels: [__meta_consul_node]
        target_label:  host

  - job_name: traefik
    metrics_path: /metrics
    scheme: https
    tls_config:
      server_name: traefik.service.home
    consul_sd_configs:
      - server: consul.service.home:8501
        scheme: https
        services: [traefik]
    relabel_configs:
      - source_labels: [__meta_consul_dc]
        target_label:  dc
      - source_labels: [__meta_consul_node]
        target_label:  host
      - source_labels: [__address__]
        action: replace
        regex: ([^:]+):.*
        replacement: $1
        target_label: __address__

  - job_name: tls-expiration
    metrics_path: /probe
    params:
      module: [http_2xx]
    consul_sd_configs:
      - server: consul.service.home:8501
        services: [nomad-client, consul-client, vault, omada-controller]
        scheme: https
    # A relabeling config that lets us scrape target through the Blackbox Exporter,
    # while labeling the resulting metrics with the probed target's URL.
    relabel_configs:
      # Set the "target" HTTP parameter to the target URL that we want to probe.
      - source_labels: [__meta_consul_address, __meta_consul_service_port]
        target_label: __param_target
        separator: ':'
        replacement: https://$1
      # Set the "instance" label to the target URL that we want to probe.
      - source_labels: [__param_target]
        target_label: instance
      # Don't actually scrape the target itself, but the Blackbox Exporter.
      - source_labels: [__meta_consul_service]
        target_label: job
      - target_label: __address__
        replacement: {{ env "NOMAD_ADDR_blackbox" }}


  - job_name: coredns
    metrics_path: /metrics
    scheme: http
    consul_sd_configs:
      - server: consul.service.home:8501
        scheme: https
        services: [coredns]
    relabel_configs:
      - source_labels: [__meta_consul_dc]
        target_label:  dc
      - source_labels: [__meta_consul_node]
        target_label:  host
      - source_labels: [__address__]
        action: replace
        regex: ([^:]+):.*
        replacement: $1:9153
        target_label: __address__

  - job_name: omada
    metrics_path: /metrics
    scheme: http
    scrape_interval: 30s
    scrape_timeout: 25s
    consul_sd_configs:
      - server: consul.service.home:8501
        scheme: https
        services: [omada-exporter]
    relabel_configs:
      - source_labels: [__meta_consul_dc]
        target_label:  dc
      - source_labels: [__meta_consul_node]
        target_label:  host

EOH

        destination   = "local/prometheus.yml"
        change_mode   = "signal"
        change_signal = "SIGHUP"
        env           = false
      }

      config {
        image = "prom/prometheus:v3.8.0"
        args = [
          "--storage.tsdb.path", "/opt/prometheus",
          "--web.listen-address", "${NOMAD_ADDR_http}",
          "--storage.tsdb.retention.time", "900d",
          "--enable-feature", join(",", [
            "promql-experimental-functions",
            "use-uncached-io",
          ]),
        ]
        # needed in order to bind to NOMAD_ADDR_http
        network_mode = "host"
        ports        = ["http"]
        volumes = [
          "local/prometheus.yml:/prometheus/prometheus.yml",
          "/etc/ssl/certs:/etc/ssl/certs:ro",
          "/clusterdata/prometheus:/opt/prometheus:rw",
        ]
      }

      resources {
        cpu    = 100
        memory = 1024
      }
    }
  }
}
