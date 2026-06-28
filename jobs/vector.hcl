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
        image = "timberio/vector:0.56.0-debian"
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

          sinks:
            vlogs:
              type: elasticsearch
              inputs: [traefik_access]
              # VictoriaLogs reached over the Consul service mesh via the sidecar
              # upstream below — Envoy provides mTLS, so this is plain local http.
              endpoints:
                - http://127.0.0.1:9428/insert/elasticsearch/
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
            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9102"
            }

            upstreams {
              destination_name = "victorialogs"
              local_bind_port  = 9428
            }

            expose {
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
