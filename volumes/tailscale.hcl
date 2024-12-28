plugin_id = "nfs"
type      = "csi"
id        = "tailscale"
name      = "tailscale"

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

context {
  server = "truenas.local"
  share  = "/mnt/pool/tailscale"
}

mount_options {
  fs_type     = "nfs"
  mount_flags = ["timeo=30", "vers=4.1", "nolock", "sync"]
}
