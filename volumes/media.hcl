plugin_id = "nfs"
type      = "csi"
id        = "media"
name      = "media"

capability {
  access_mode     = "multi-node-multi-writer"
  attachment_mode = "file-system"
}

context {
  server = "nasty.node.home"
  share  = "/volume1/media"
}

mount_options {
  fs_type     = "nfs"
  mount_flags = ["timeo=30", "vers=4.1", "nolock", "sync"]
}
