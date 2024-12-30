plugin_id = "nfs"
type      = "csi"
id        = "postgres"
name      = "postgres"

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

context {
  server = "nasty.local"
  share  = "/volume1/postgres"
  subDir = "15"
}

mount_options {
  fs_type     = "nfs"
  mount_flags = ["timeo=30", "vers=4.1", "nolock", "sync"]
}
