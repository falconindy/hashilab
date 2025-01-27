job "csi-iscsi-plugin" {
  datacenters = ["dc1"]
  priority = 100
  # you can run node plugins as service jobs as well, but this ensures
  # that all nodes in the DC have a copy
  type = "system"

  group "plugin" {
    task "plugin" {
      driver = "docker"

      env {
        CSI_NODE_ID = "${attr.unique.hostname}"

        # if you run into a scenario where your iscsi volumes are zeroed each time they are mounted,
        # you can configure the fs detection system used with the following envvar:
        #FILESYSTEM_TYPE_DETECTION_STRATEGY = "blkid"
      }

      config {
        image = "docker.io/democraticcsi/democratic-csi:latest"

        args = [
          "--csi-version=1.5.0",
          # must match the csi_plugin.id attribute below
          "--csi-name=org.democratic-csi.iscsi",
          "--driver-config-file=${NOMAD_TASK_DIR}/driver-config-file.yaml",
          "--log-level=debug",
          "--csi-mode=node",
          "--server-socket=/csi/csi.sock",
        ]

        # node plugins must run as privileged jobs because they
        # mount disks to the host
        privileged = true
        ipc_mode = "host"
        network_mode = "host"

        mount {
          type = "bind"
          target = "/host"
          source = "/"
          readonly = false
        }

        # if you run into a scenario where your iscsi volumes are zeroed each time they are mounted,
        # you can try uncommenting the following additional mount block:
        mount {
          type     = "bind"
          target   = "/run/udev"
          source   = "/run/udev"
          readonly = true
        }
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
  {{ with secret "kv/data/default/csi-iscsi-plugin" }}
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
        type      = "node"
        mount_dir = "/csi"
      }

      resources {
        cpu    = 50
        memory = 128
      }
    }
  }
}
