job "csi-iscsi-controller" {
  datacenters = ["dc1"]

  group "controller" {
    task "controller" {
      driver = "docker"

      config {
        image = "docker.io/democraticcsi/democratic-csi:latest"

        args = [
          "--csi-version=1.5.0",
          # must match the csi_plugin.id attribute below
          "--csi-name=org.democratic-csi.iscsi",
          "--driver-config-file=${NOMAD_TASK_DIR}/driver-config-file.yaml",
          "--log-level=info",
          "--csi-mode=controller",
          "--server-socket=/csi/csi.sock",
        ]
      }

      vault {}

      identity {
        name = "vault_default"
        aud  = ["vault.io"]
        ttl  = "1h"
      }

      template {
        destination = "${NOMAD_TASK_DIR}/driver-config-file.yaml"

        data = <<EOH
driver: synology-iscsi
httpConnection:
  protocol: "http"
  host: "nasty.node.home"
  port: 5000
  username: "nomad"
  {{ with secret "kv/data/default/csi-iscsi-controller" }}
  password: {{ .Data.data.nasty_api_password }}
  {{ end }}
  allowInsecure: true
  session: "democratic-csi"

iscsi:
  targetPortal: "nasty.node.home:3260"
  targetPortals: []
  interface: ""
  baseiqn: "iqn.2000-01.com.synology:csi."

  namePrefix: "nomad-"
  nameSuffix: ""

  lunTemplate:
    type: THIN

  lunSnapshotTemplate:
    is_locked: true
    is_app_consistent: true

  targetTemplate:
    auth_type: 0
    max_sessions: 0
EOH
      }

      csi_plugin {
        # must match --csi-name arg
        id        = "org.democratic-csi.iscsi"
        type      = "controller"
        mount_dir = "/csi"
      }

      resources {
        cpu    = 50
        memory = 128
      }
    }
  }
}
