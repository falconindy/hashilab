job "grafana" {
  datacenters = ["dc1"]
  type        = "service"

  ui {
    description = "An open and composable observability and data visualization platform"
    link {
      label = "Upstream"
      url   = "https://grafana.com/oss/grafana/"
    }
    link {
      label = "GitHub"
      url   = "https://github.com/grafana/grafana"
    }
    link {
      label = "Docker Hub"
      url   = "https://hub.docker.com/r/grafana/grafana"
    }
  }

  group "grafana" {
    network {
      mode = "bridge"

      dns {
        servers = ["172.17.0.1"]
      }

      port "envoy_metrics" { to = 9102 }
    }

    task "server" {
      driver = "docker"
      user   = "1000:1000"
      config {
        image       = "grafana/grafana:13.1.1"
        userns_mode = "host"

        cap_drop     = ["all"]
        security_opt = ["no-new-privileges=true"]

        volumes = [
          "/clusterdata/grafana:/var/lib/grafana:rw",
          "local/victorialogs.yml:/etc/grafana/provisioning/datasources/victorialogs.yml:ro",
          "local/dashboards.yml:/etc/grafana/provisioning/dashboards/hashilab.yml:ro",
        ]
      }

      # Provision the VictoriaLogs datasource declaratively. Reached over the
      # Consul service mesh (transparent proxy) — Envoy handles mTLS, so plain
      # http. The victoriametrics-logs-datasource plugin is preinstalled below.
      template {
        data        = <<-EOF
          apiVersion: 1
          # Delete any pre-existing VictoriaLogs datasource first so it is recreated
          # with the stable uid below. Grafana won't change an existing datasource's
          # uid on update, and provisioned dashboards reference it by uid.
          deleteDatasources:
            - name: VictoriaLogs
              orgId: 1
          datasources:
            - name: VictoriaLogs
              type: victoriametrics-logs-datasource
              uid: victorialogs
              access: proxy
              url: http://victorialogs.virtual.home
        EOF
        destination = "local/victorialogs.yml"
      }

      # Dashboard provider. Dashboards live as standalone JSON files in the repo
      # (grafana/dashboards/*.json) and are rsynced to /clusterdata/grafana/dashboards
      # by bin/deploy-grafana-dashboards — NOT embedded in this job. Grafana polls the
      # folder and hot-reloads changes, so editing a dashboard needs no job redeploy.
      template {
        data        = <<-EOF
          apiVersion: 1
          providers:
            - name: hashilab
              type: file
              allowUiUpdates: true
              updateIntervalSeconds: 30
              options:
                path: /var/lib/grafana/dashboards
                foldersFromFilesStructure: true
        EOF
        destination = "local/dashboards.yml"
      }

      env {
        GF_SERVER_ROOT_URL    = "https://grafana.service.home"
        GF_PATHS_DATA         = "/var/lib/grafana"
        GF_AUTH_BASIC_ENABLED = "false"
        GF_PLUGINS_PREINSTALL = "victoriametrics-logs-datasource"

        GF_SECURITY_ALLOW_EMBEDDING = "true"

        GF_USERS_ALLOW_SIGN_UP = "false"
      }

      resources {
        cpu    = 100
        memory = 1024
      }
    }

    service {
      name = "grafana"
      port = 3000

      tags = [
        "traefik.enable=true",
      ]

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}"
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
        path     = "/api/health"
        interval = "10s"
        timeout  = "2s"
        expose   = true
      }
    }
  }
}
