plugin_id = "nfs"
type      = "csi"
id        = "omada-controller-cert"
name      = "omada-controller-cert"

capability {
  access_mode     = "multi-node-reader-only"
  attachment_mode = "file-system"
}

context {
  server = "nasty.node.home"
  share  = "/volume1/omada-controller"
  subDir = "cert"
}

mount_options {
  fs_type     = "nfs"
  mount_flags = ["timeo=30", "vers=4.1"]
}
