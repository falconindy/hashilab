# Used by the traefik job (role traefik) to issue its *.service.home wildcard
# straight from pki_int via pkiCert. The pki_int `traefik` role itself limits
# what names can be signed.
path "pki_int/issue/traefik" {
  capabilities = ["update"]
}
