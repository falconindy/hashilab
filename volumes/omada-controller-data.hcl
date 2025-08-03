plugin_id = "nfs"
type      = "csi"
id        = "omada-controller-data"
name      = "omada-controller-data"

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

context {
  server = "nasty.node.home"
  share  = "/volume1/omada-controller"
  subDir = "data"
}

mount_options {
  fs_type     = "nfs"
  mount_flags = ["timeo=30", "vers=4.1", "nolock", "sync"]
}
