plugin_id = "nfs"
type      = "csi"
id        = "www"
name      = "www"

capability {
  access_mode     = "multi-node-reader-only"
  attachment_mode = "file-system"
}

context {
  server = "nasty.node.home"
  share  = "/volume1/www"
}

mount_options {
  fs_type     = "nfs"
  mount_flags = ["timeo=30", "vers=4.1", "nolock"]
}

