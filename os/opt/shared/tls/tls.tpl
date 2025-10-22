{{ with secret "pki_int_internal/cert/ca_chain" }}{{ .Data.ca_chain }}{{ end }}
