id           = "tailscale"
name         = "tailscale"
type         = "csi"
plugin_id    = "org.democratic-csi.iscsi"
capacity_min = "10MiB"
capacity_max = "10MiB"

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "block-device"
}

context {
  node_attach_driver = "iscsi"
}

mount_options {
  fs_type     = "ext4"
  mount_flags = ["noatime"]
}
