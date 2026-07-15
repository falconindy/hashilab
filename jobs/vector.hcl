job "vector" {
  datacenters = ["*"]
  type        = "system"

  ui {
    description = "A lightweight, high-throughput observability data pipeline (ships Docker logs to Loki)"
    link {
      label = "Upstream"
      url   = "https://vector.dev"
    }
    link {
      label = "GitHub"
      url   = "https://github.com/vectordotdev/vector"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/r/timberio/vector"
    }
  }

  group "vector" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "envoy_metrics" { to = 9102 }
      port "vector_metrics" {}
    }

    task "server" {
      driver = "docker"

      config {
        image = "timberio/vector:0.57.0-debian"
        args  = ["--config-yaml", "/etc/vector/vector.yml"]

        volumes = [
          "local/vector.yml:/etc/vector/vector.yml",
          "/var/run/docker.sock:/var/run/docker.sock:ro",
        ]
      }

      env {
        # The node's real hostname, interpolated by Nomad at placement time.
        # Used as the "node" log field — Vector's own .host is just its
        # container id in bridge mode, which is useless.
        VECTOR_NODE = "${attr.unique.hostname}"
      }

      resources {
        cpu    = 100
        memory = 96
      }

      template {
        data        = <<-EOF
          data_dir: /alloc/data

          sources:
            docker:
              type: docker_logs

            internal:
              type: internal_metrics

          transforms:
            # Don't ship Vector's own logs back through Vector.
            not_vector:
              type: filter
              inputs: [docker]
              condition: '.label."com.hashicorp.nomad.job_name" != "vector"'

            nomad_meta:
              type: remap
              inputs: [not_vector]
              source: |
                # Promote the Nomad docker-driver labels (see extra_labels in the
                # client config) to first-class fields, then drop the noisy label map.
                .nomad_job   = string(.label."com.hashicorp.nomad.job_name") ?? "unknown"
                .nomad_group = string(.label."com.hashicorp.nomad.task_group_name") ?? "unknown"
                .nomad_task  = string(.label."com.hashicorp.nomad.task_name") ?? "unknown"
                .node        = get_env_var("VECTOR_NODE") ?? "unknown"
                del(.label)
                del(.host)

            # Parse Traefik's JSON access logs (the traefik / traefik-ingress jobs
            # set accessLog.format=json) into first-class fields, so ClientHost,
            # status, host/path and latency are filterable in VictoriaLogs/Grafana.
            # We also synthesize a compact, human-readable _msg so the log viewers
            # stay legible instead of showing a raw JSON blob. Scoped by job name;
            # Traefik's own (non-JSON) app logs fall through untouched.
            traefik_access:
              type: remap
              inputs: [nomad_meta]
              source: |
                if (.nomad_job == "traefik") || (.nomad_job == "traefik-ingress") {
                  msg = to_string(.message) ?? ""
                  if starts_with(msg, "{") {
                    parsed, err = parse_json(msg)
                    if err == null {
                      obj = object(parsed) ?? {}

                      .ClientHost            = obj.ClientHost
                      .RequestMethod         = obj.RequestMethod
                      .RequestHost           = obj.RequestHost
                      .RequestPath           = obj.RequestPath
                      .RequestProtocol       = obj.RequestProtocol
                      .RouterName            = obj.RouterName
                      .ServiceName           = obj.ServiceName
                      .DownstreamStatus      = obj.DownstreamStatus
                      .OriginStatus          = obj.OriginStatus
                      .RetryAttempts         = obj.RetryAttempts
                      .RequestContentSize    = obj.RequestContentSize
                      .DownstreamContentSize = obj.DownstreamContentSize

                      # Traefik reports Duration in nanoseconds; expose milliseconds.
                      dur = (to_float(obj.Duration) ?? 0.0) / 1000000.0
                      .DurationMs = dur

                      # Compact access line, e.g. "1.2.3.4 GET host.tld/path -> 200 (12ms)".
                      # to_string() is fallible on dynamic fields, so coalesce each part.
                      cli  = to_string(obj.ClientHost) ?? "-"
                      meth = to_string(obj.RequestMethod) ?? "-"
                      host = to_string(obj.RequestHost) ?? "-"
                      path = to_string(obj.RequestPath) ?? ""
                      code = to_string(obj.DownstreamStatus) ?? "-"
                      durs = to_string(round(dur))
                      .message = cli + " " + meth + " " + host + path + " -> " + code + " (" + durs + "ms)"
                    }
                  }
                }

            # Infer a "level" field so VictoriaLogs/vmui can colour severity —
            # it reads the first present of: level, lvl, log_level, severity, ...
            # Reliable for structured logs (JSON loggers, and level=/severity=
            # logfmt — which covers the Go apps); best-effort for a leading
            # [LEVEL] tag; left unset (shown as "other") when nothing matches.
            log_level:
              type: remap
              inputs: [traefik_access]
              source: |
                # Traefik access logs are structured but levelless — derive a
                # level from the HTTP status so 5xx (server errors) stand out.
                # 4xx are client errors, not something to flag — treat as info.
                if !exists(.level) && exists(.DownstreamStatus) {
                  st = to_int(.DownstreamStatus) ?? 0
                  if st >= 500 {
                    .level = "error"
                  } else if st > 0 {
                    .level = "info"
                  }
                }

                if !exists(.level) {
                  msg = to_string(.message) ?? ""
                  lvl = ""

                  # JSON loggers: pull a level/severity key.
                  if starts_with(msg, "{") {
                    parsed, err = parse_json(msg)
                    if err == null {
                      o = object(parsed) ?? {}
                      lvl = string(o.level) ?? string(o.severity) ?? string(o.lvl) ?? string(o.severityText) ?? string(o.SeverityText) ?? ""
                    }
                  }

                  # logfmt (Go apps, the registry, ...): level=info / lvl="warn".
                  if lvl == "" {
                    m, e = parse_regex(msg, r'(?i)\b(?:level|lvl|severity)="?(?P<l>[a-z]+)')
                    if e == null { lvl = string(m.l) ?? "" }
                  }

                  # Bracketed level anywhere, e.g. "... [info] ..." / "[ERROR]"
                  # (covers loggers that put it after a timestamp, like teslamate).
                  if lvl == "" {
                    m2, e2 = parse_regex(msg, r'\[(?P<l>(?i:trace|debug|info|warn|warning|notice|error|err|fatal|critical|crit|panic))\]')
                    if e2 == null { lvl = string(m2.l) ?? "" }
                  }

                  # A capitalised level word as a standalone token — UPPER or Title
                  # case only, so lowercase prose ("no error here") is ignored.
                  # Covers "06-28 10:25:53 Warn ..." (jackett) and "ERROR: ...".
                  if lvl == "" {
                    m3, e3 = parse_regex(msg, r'\b(?P<l>TRACE|DEBUG|INFO|WARN|WARNING|NOTICE|ERROR|FATAL|CRITICAL|PANIC|Trace|Debug|Info|Warn|Warning|Notice|Error|Fatal|Critical|Panic)\b')
                    if e3 == null { lvl = string(m3.l) ?? "" }
                  }

                  if lvl != "" {
                    .level = downcase(lvl)
                  }
                }

                # Web access logs in Common/Combined Log Format (nginx static-www,
                # the registry's own access line, ...) carry no level — derive it
                # from the HTTP status and expose method/path/status as fields.
                if !exists(.level) {
                  am, ae = parse_regex(to_string(.message) ?? "", r'^\S+ \S+ \S+ \[[^\]]+\] "(?P<method>[A-Z]+) (?P<path>\S+)[^"]*" (?P<status>\d{3})')
                  if ae == null {
                    code = to_int(am.status) ?? 0
                    .http_method = am.method
                    .http_path   = am.path
                    .http_status = code
                    if code >= 500 {
                      .level = "error"
                    } else {
                      .level = "info"
                    }
                  }
                }

          sinks:
            vlogs:
              type: elasticsearch
              inputs: [log_level]
              # VictoriaLogs reached over the Consul service mesh via transparent
              # proxy — Envoy provides mTLS, so this is plain http to the mesh
              # virtual address.
              endpoints:
                - http://victorialogs.virtual.home/insert/elasticsearch/
              api_version: v8
              compression: gzip
              healthcheck:
                enabled: false
              # Tell VictoriaLogs which fields carry the message, time, and the
              # low-cardinality stream identity. Everything else lands as fields.
              query:
                _msg_field: message
                _time_field: timestamp
                _stream_fields: nomad_job,nomad_group,nomad_task,node

            prometheus:
              type: prometheus_exporter
              inputs: [internal]
              address: 0.0.0.0:9598
        EOF
        destination = "local/vector.yml"
      }
    }

    service {
      name = "vector"
      port = 9598

      meta {
        envoy_metrics_port  = "${NOMAD_HOST_PORT_envoy_metrics}"
        vector_metrics_port = "${NOMAD_HOST_PORT_vector_metrics}"
      }

      connect {
        sidecar_service {
          proxy {
            transparent_proxy {
              no_dns = true
            }

            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9102"
            }

            expose {
              path {
                path            = "/metrics"
                protocol        = "http"
                local_path_port = 9102
                listener_port   = "envoy_metrics"
              }

              path {
                path            = "/metrics"
                protocol        = "http"
                local_path_port = 9598
                listener_port   = "vector_metrics"
              }
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
}
