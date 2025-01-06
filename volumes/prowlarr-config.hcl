plugin_id = "nfs"
type      = "csi"
id        = "prowlarr-config"
name      = "prowlarr-config"

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

context {
  server = "nasty.node.home"
  share  = "/volume1/media"
  subDir = "config/prowlarr"
}

mount_options {
  fs_type     = "nfs"
  mount_flags = ["timeo=30", "vers=4.1", "nolock", "sync"]
}
