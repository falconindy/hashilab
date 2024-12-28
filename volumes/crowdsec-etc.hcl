plugin_id = "nfs"
type      = "csi"
id        = "crowdsec-etc"
name      = "crowdsec-etc"

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

context {
  server = "nasty.local"
  share  = "/volume1/crowdsec"
  subDir = "etc"
}

mount_options {
  fs_type     = "nfs"
  mount_flags = ["timeo=30", "vers=4.1", "nolock", "sync"]
}

