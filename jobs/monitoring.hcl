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

  group "prometheus" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "envoy_metrics" { to = 9102 }
    }

    # Blackbox is consumed only by prometheus, so it lives in the same group
    # and is reached over loopback.
    task "blackbox" {
      driver = "docker"

      config {
        image = "prom/blackbox-exporter:v0.28.0"

        cap_drop     = ["all"]
        security_opt = ["no-new-privileges=true"]

        args = [
          "--config.file", "local/blackbox.yml",
        ]
        volumes = [
          "/etc/ssl/certs/ca-certificates.crt:/etc/ssl/certs/ca-certificates.crt:ro",
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

    # consul-exporter is consumed only by prometheus (feeds the
    # ConsulCheckCritical alert), so it lives in the same group and is
    # reached over loopback, same as blackbox above.
    task "consul-health" {
      driver = "docker"

      config {
        image = "prom/consul-exporter:v0.13.0"

        cap_drop     = ["all"]
        security_opt = ["no-new-privileges=true"]

        args = [
          "--consul.server=https://consul.service.home:8501",
          "--consul.ca-file=/etc/ssl/certs/ca-certificates.crt",
          "--web.listen-address=127.0.0.1:9107",
        ]
        volumes = [
          "/etc/ssl/certs/ca-certificates.crt:/etc/ssl/certs/ca-certificates.crt:ro",
        ]
      }

      resources {
        cpu    = 50
        memory = 64
      }
    }

    task "server" {
      driver = "docker"
      user   = "1000:2000"

      # Provisions a Consul token from this task's workload identity (injected as
      # CONSUL_TOKEN, used as the bearer_token on the `consul` scrape job below).
      # Under default_policy = "deny" the anonymous token is read-only and can't
      # hit /v1/agent/metrics (agent:read); this token carries agent:read via the
      # `prometheus` role (tofu module.consul_nomad_wi). Service discovery
      # (consul_sd_configs) still rides the anonymous catalog read.
      consul {}

      # main configuration file
      template {
        data = <<-EOF
          global:
            scrape_interval:     15s # Scrape every 15 seconds (default 1m)
            evaluation_interval: 15s # Evaluate rules every 15 seconds (default 1m)

          rule_files:
            - /prometheus/alerts.yml

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
              # /v1/agent/metrics requires agent:read; the anonymous token is
              # read-only on catalog/nodes under default_policy=deny. This is the
              # task's workload-identity Consul token (prometheus role, agent:read).
              bearer_token: {{ env "CONSUL_TOKEN" }}
              tls_config:
                server_name: consul.service.home
              consul_sd_configs:
                - server: consul.service.home:8501
                  scheme: https
                  # Consul only registers a "consul" service that allows
                  # discovery of Consul servers, but makes no such arrangements
                  # for discovering *clients*. However, Nomad does this via the
                  # nomad-client service, so leverage that for scraping Consul
                  # clients. Naturally, this implicitly defines a coupling
                  # requirement that if Nomad is running on a machine, then so
                  # is Consul.
                  services: [nomad-client]
              relabel_configs:
                - source_labels: [__meta_consul_dc]
                  target_label:  dc
                - source_labels: [__meta_consul_node]
                  target_label:  host
                - source_labels: [__address__]
                  action: replace
                  regex: ([^:]+):.*
                  replacement: $1:8501
                  target_label: __address__

            - job_name: vault
              metrics_path: /v1/sys/metrics
              scheme: https
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
                  scheme: https
                  services: [vault, omada-controller]
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

            - job_name: consul-health
              # consul-exporter (task "consul-health") is colocated with
              # prometheus and reached over loopback, same as blackbox below.
              # It turns per-check health state into a scrapable metric
              # (consul_health_service_status) for the ConsulCheckCritical
              # alert.
              static_configs:
                - targets: ["127.0.0.1:9107"]

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

      # Alerting rules. Uses [[ ]] delimiters (rather than the job's default
      # {{ }}) purely so Prometheus's own annotation templating syntax
      # ({{ $labels.foo }}, {{ $value }}) passes through untouched instead of
      # being consumed by Nomad's consul-template rendering.
      template {
        left_delimiter  = "[["
        right_delimiter = "]]"
        data            = <<-EOF
          groups:
            - name: hashilab
              rules:
                # --- Raft leadership: Consul, Nomad, Vault ---
                - alert: ConsulNoLeader
                  expr: max(consul_server_isLeader) == 0
                  for: 2m
                  labels:
                    severity: critical
                  annotations:
                    summary: "Consul has no elected leader"
                    description: "No Consul server has reported itself as leader for at least 2 minutes."

                - alert: NomadNoLeader
                  # nomad_nomad_autopilot_healthy is only emitted by the
                  # current Nomad leader (autopilot state is leader-computed),
                  # so its absence means no leader is elected.
                  expr: absent(nomad_nomad_autopilot_healthy)
                  for: 2m
                  labels:
                    severity: critical
                  annotations:
                    summary: "Nomad has no elected leader"
                    description: "No Nomad server has reported autopilot health (leader-only metric) for at least 2 minutes."

                - alert: VaultNoActiveNode
                  expr: max(vault_core_active) == 0 or absent(vault_core_active)
                  for: 2m
                  labels:
                    severity: critical
                  annotations:
                    summary: "Vault has no active node"
                    description: "No Vault server has reported itself as active (unsealed leader) for at least 2 minutes."

                - alert: ConsulLeaderFlapping
                  # Threshold sits above what a normal rolling reboot of the
                  # 3 servers produces (~3 handoffs), so it's insensitive to
                  # planned reboots.
                  expr: sum(increase(consul_raft_state_leader[1h])) > 3
                  labels:
                    severity: warning
                  annotations:
                    summary: "Consul leadership is flapping"
                    description: "Consul has elected more than 3 leaders in the last hour."

                - alert: NomadLeaderFlapping
                  expr: sum(increase(nomad_raft_state_leader[1h])) > 3
                  labels:
                    severity: warning
                  annotations:
                    summary: "Nomad leadership is flapping"
                    description: "Nomad has elected more than 3 leaders in the last hour."

                - alert: VaultLeaderFlapping
                  expr: sum(increase(vault_raft_state_leader[1h])) > 3
                  labels:
                    severity: warning
                  annotations:
                    summary: "Vault leadership is flapping"
                    description: "Vault has elected more than 3 active nodes in the last hour."

                # --- Nomad jobs ---
                - alert: NomadJobHardDown
                  # 0 running, plus either stuck unplaceable (queued > 0, e.g.
                  # a constraint no node satisfies) or a recent failure. This
                  # still doesn't fire for a clean `job stop` or a
                  # periodic/batch job idling between runs: both leave
                  # running=0, queued=0, and no recent failed increase.
                  expr: nomad_nomad_job_summary_running == 0 and (nomad_nomad_job_summary_queued > 0 or increase(nomad_nomad_job_summary_failed[10m]) > 0)
                  for: 5m
                  labels:
                    severity: critical
                  annotations:
                    summary: "Nomad job {{ $labels.exported_job }}/{{ $labels.task_group }} is down"
                    description: "Task group has 0 running and 0 queued allocations after recent placement failures."

                - alert: NomadAllocationsRestartingFrequently
                  # nomad_client_allocations_restart is host-level only (no
                  # job/task_group label on this Nomad version), so this
                  # points at a node, not a specific job.
                  expr: increase(nomad_client_allocations_restart_count[10m]) > 3
                  labels:
                    severity: warning
                  annotations:
                    summary: "Allocations restarting frequently on {{ $labels.host }}"
                    description: "More than 3 allocation restarts on this Nomad client in the last 10 minutes."

                # --- Consul health checks ---
                - alert: ConsulCheckCritical
                  expr: consul_health_service_status{status="critical"} == 1
                  for: 5m
                  labels:
                    severity: critical
                  annotations:
                    summary: "Consul check critical: {{ $labels.service_name }}"
                    description: "A Consul health check has been critical for more than 5 minutes."

                # --- PKI ---
                - alert: VaultPkiIntInternalIssuanceFailing
                  expr: increase(vault_pki_int_internal_issue_failure[15m]) > 0
                  labels:
                    severity: critical
                  annotations:
                    summary: "Vault pki_int_internal certificate issuance is failing"
                    description: "At least one certificate issuance failure on the pki_int_internal mount in the last 15 minutes."

                # --- Extras: cheap wins on metrics already scraped ---
                - alert: TargetDown
                  expr: up == 0
                  for: 5m
                  labels:
                    severity: warning
                  annotations:
                    summary: "Scrape target down: {{ $labels.job }} on {{ $labels.host }}"
                    description: "Prometheus has failed to scrape this target for more than 5 minutes."

                - alert: VaultSealed
                  expr: vault_core_unsealed == 0
                  for: 2m
                  labels:
                    severity: critical
                  annotations:
                    summary: "Vault node sealed: {{ $labels.host }}"
                    description: "A Vault node has been sealed for more than 2 minutes."

                - alert: CertExpiringSoon
                  expr: (probe_ssl_earliest_cert_expiry - time()) < 14 * 86400
                  labels:
                    severity: warning
                  annotations:
                    summary: "TLS cert expiring soon: {{ $labels.instance }}"
                    description: "Certificate probed via blackbox_exporter expires in under 14 days."

                - alert: ConsulAgentCertExpiringSoon
                  expr: consul_agent_tls_cert_expiry < 14 * 86400
                  labels:
                    severity: warning
                  annotations:
                    summary: "Consul agent TLS cert expiring soon: {{ $labels.host }}"
                    description: "Consul agent cert on this node expires in under 14 days."

                - alert: NomadAgentCertExpiringSoon
                  expr: nomad_agent_tls_cert_expiration_seconds < 14 * 86400
                  labels:
                    severity: warning
                  annotations:
                    summary: "Nomad agent TLS cert expiring soon: {{ $labels.host }}"
                    description: "Nomad agent cert on this node expires in under 14 days."

                - alert: X509WatchedCertExpiringSoon
                  expr: (x509_cert_not_after - time()) < 14 * 86400
                  labels:
                    severity: warning
                  annotations:
                    summary: "Watched x509 cert expiring soon: {{ $labels.filepath }} on {{ $labels.instance }}"
                    description: "Cert watched by x509-exporter (Vault raft client cert, root/intermediate CAs) expires in under 14 days."

                # job="traefik" (internal, pki_int) deliberately excluded: its
                # ACME store keeps entries for decommissioned services (see
                # homelabdash's ACME Certificates/Orphaned reconciliation),
                # which would make this noisy. traefik-ingress requests a
                # single static wildcard (jobs/traefik-ingress.hcl), so
                # there's no such ambiguity here.
                - alert: PublicWildcardCertExpiringSoon
                  expr: (traefik_tls_certs_not_after{job="traefik-ingress"} - time()) < 14 * 86400
                  labels:
                    severity: warning
                  annotations:
                    summary: "Public wildcard TLS cert expiring soon: {{ $labels.sans }}"
                    description: "The falconindy.com wildcard cert (Let's Encrypt via Cloudflare DNS-01) expires in under 14 days."
        EOF

        destination   = "local/alerts.yml"
        change_mode   = "signal"
        change_signal = "SIGHUP"
        env           = false
      }

      config {
        image = "prom/prometheus:v3.13.2"

        cap_drop     = ["all"]
        security_opt = ["no-new-privileges=true"]

        args = [
          "--storage.tsdb.path", "/opt/prometheus",
          "--storage.tsdb.retention.time", "365d",
          "--enable-feature", join(",", [
            "promql-experimental-functions",
            "use-uncached-io",
          ]),
        ]
        volumes = [
          "local/prometheus.yml:/prometheus/prometheus.yml",
          "local/alerts.yml:/prometheus/alerts.yml",
          "/etc/ssl/certs/ca-certificates.crt:/etc/ssl/certs/ca-certificates.crt:ro",
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
        # Lets the browser (homelabdash) fetch /api/v1/alerts cross-origin
        # from d.service.home. Internal Traefik only, so this doesn't widen
        # public exposure.
        "traefik.http.routers.prometheus.middlewares=cors-allow-all@file",
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
