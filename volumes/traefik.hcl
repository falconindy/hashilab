plugin_id = "nfs"
type      = "csi"
id        = "traefik"
name      = "traefik"

capability {
  access_mode     = "multi-node-reader-only"
  attachment_mode = "file-system"
}

capability {
  access_mode     = "multi-node-multi-writer"
  attachment_mode = "file-system"
}

context {
  server = "nasty.node.home"
  share  = "/volume1/traefik"
}

mount_options {
  fs_type     = "nfs"
  mount_flags = ["timeo=30", "vers=4.1", "nolock", "sync"]
}

