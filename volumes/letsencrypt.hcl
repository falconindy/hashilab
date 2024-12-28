plugin_id = "nfs"
type      = "csi"
id        = "letsencrypt"
name      = "letsencrypt"

capability {
  access_mode     = "multi-node-multi-writer"
  attachment_mode = "file-system"
}

context {
  server = "nasty.local"
  share  = "/volume1/letsencrypt"
}

mount_options {
  fs_type     = "nfs"
  mount_flags = ["timeo=30", "vers=4.1", "nolock", "sync"]
}
