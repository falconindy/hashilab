job "monitoring" {
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

  group "blackbox-exporter" {
    network {
      mode = "bridge"

      port "envoy_metrics" { to = 9102 }
    }

    task "server" {
      driver = "docker"

      config {
        image = "prom/blackbox-exporter:v0.28.0"

        cap_drop     = ["all"]
        security_opt = ["no-new-privileges=true"]

        args = [
          "--config.file", "local/blackbox.yml",
        ]
        volumes = [
          "/etc/ssl/certs:/etc/ssl/certs:ro",
        ]
      }

      resources {
        cpu    = 100
        memory = 128
      }

      template {
        data        = <<-EOF
          modules:
            tls_connect:
              prober: tcp
              timeout: 5s
              tcp:
                tls: true
        EOF
        destination = "local/blackbox.yml"
      }
    }

    service {
      name = "blackbox-exporter"
      port = 9115

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
  }

  group "prometheus" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "envoy_metrics" { to = 9102 }
    }

    task "server" {
      driver = "docker"
      user   = "1000:2000"

      vault {}

      # main configuration file
      template {
        data = <<-EOF
          global:
            scrape_interval:     15s # Scrape every 15 seconds (default 1m)
            evaluation_interval: 15s # Evaluate rules every 15 seconds (default 1m)

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

            - job_name: traefik-ingress
              metrics_path: /metrics
              consul_sd_configs:
                - server: consul.service.home:8501
                  scheme: https
                  services: [traefik-ingress]
              relabel_configs:
                - source_labels: [__meta_consul_dc]
                  target_label:  dc
                - source_labels: [__meta_consul_node]
                  target_label:  host
                # The service port (8080) is the in-mesh dashboard entrypoint and
                # isn't bound on the host; scrape the host-mapped metrics port.
                - source_labels: [__address__, __meta_consul_service_metadata_metrics_port]
                  regex: ([^:]+)(?::\d+)?;(\d+)
                  replacement: $1:$2
                  target_label: __address__

            - job_name: tls-expiration
              metrics_path: /probe
              params:
                module: [tls_connect]
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
                  replacement: $1
                # Set the "instance" label to the target URL that we want to probe.
                - source_labels: [__param_target]
                  target_label: instance
                # Don't actually scrape the target itself, but the Blackbox Exporter.
                - source_labels: [__meta_consul_service]
                  target_label: job
                - target_label: __address__
                  replacement: 127.0.0.1:9115

            - job_name: tls-client-expiration
              consul_sd_configs:
                - server: consul.service.home:8501
                  scheme: https
                  services: [x509-exporter]
              relabel_configs:
                - source_labels: [__meta_consul_service]
                  action: keep
                  regex: x509-exporter
                - source_labels: [__meta_consul_node]
                  target_label: instance
                - source_labels: [__meta_consul_service]
                  target_label: job

            - job_name: envoy-consul
              consul_sd_configs:
                - server: consul.service.home:8501
                  scheme: https
              relabel_configs:
                - source_labels: [__meta_consul_service]
                  action: drop
                  regex: (.+)-sidecar-proxy
                - source_labels: [__meta_envoy_cluster_name] # drop metrics for Envoy internal traffic
                  action: drop
                  regex: local_agent
                - source_labels: [__meta_envoy_cluster_name]
                  action: drop
                  regex: local_app
                - source_labels: [__meta_envoy_cluster_name]
                  action: drop
                  regex: self_admin
                - source_labels: [__meta_consul_service_metadata_envoy_metrics_port]
                  action: keep
                  regex: (.+)
                - source_labels: [__address__, __meta_consul_service_metadata_envoy_metrics_port]
                  regex: ([^:]+)(?::\d+)?;(\d+)
                  replacement: $1:$2
                  target_label: __address__
                - source_labels: [__meta_consul_node]
                  target_label:  host
                - source_labels: [__meta_consul_service]
                  regex: "(.+)"
                  replacement: $1
                  target_label: "service_name"

            - job_name: 'node-exporter'
              consul_sd_configs:
                - server: consul.service.home:8501
                  scheme: https
                  services: [node-exporter]
              relabel_configs:
                - source_labels: [__meta_consul_dc]
                  target_label:  dc
                - source_labels: [__meta_consul_node]
                  target_label:  instance

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

            - job_name: victorialogs
              metrics_path: /metrics
              consul_sd_configs:
                - server: consul.service.home:8501
                  scheme: https
                  services: [victorialogs]
              relabel_configs:
                # Scrape VictoriaLogs' metrics via the sidecar-exposed port.
                - source_labels: [__meta_consul_service_metadata_vl_metrics_port]
                  action: keep
                  regex: (.+)
                - source_labels: [__address__, __meta_consul_service_metadata_vl_metrics_port]
                  regex: ([^:]+)(?::\d+)?;(\d+)
                  replacement: $1:$2
                  target_label: __address__
                - source_labels: [__meta_consul_dc]
                  target_label:  dc
                - source_labels: [__meta_consul_node]
                  target_label:  host

            - job_name: vector
              metrics_path: /metrics
              consul_sd_configs:
                - server: consul.service.home:8501
                  scheme: https
                  services: [vector]
              relabel_configs:
                # Scrape Vector's own pipeline metrics via the sidecar-exposed port.
                - source_labels: [__meta_consul_service_metadata_vector_metrics_port]
                  action: keep
                  regex: (.+)
                - source_labels: [__address__, __meta_consul_service_metadata_vector_metrics_port]
                  regex: ([^:]+)(?::\d+)?;(\d+)
                  replacement: $1:$2
                  target_label: __address__
                - source_labels: [__meta_consul_dc]
                  target_label:  dc
                - source_labels: [__meta_consul_node]
                  target_label:  host
        EOF

        destination   = "local/prometheus.yml"
        change_mode   = "signal"
        change_signal = "SIGHUP"
        env           = false
      }

      config {
        image = "prom/prometheus:v3.12.0"

        cap_drop     = ["all"]
        security_opt = ["no-new-privileges=true"]

        args = [
          "--storage.tsdb.path", "/opt/prometheus",
          "--storage.tsdb.retention.time", "900d",
          "--enable-feature", join(",", [
            "promql-experimental-functions",
            "use-uncached-io",
          ]),
        ]
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

    service {
      name = "prometheus"
      port = 9090

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=true",
      ]

      connect {
        sidecar_service {
          proxy {
            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9102"
            }

            upstreams {
              destination_name = "blackbox-exporter"
              local_bind_port  = 9115
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
        path     = "/-/healthy"
        name     = "http"
        interval = "5s"
        timeout  = "2s"
        expose   = true
      }
    }
  }
}
