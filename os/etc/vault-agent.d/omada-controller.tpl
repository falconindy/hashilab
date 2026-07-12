{{- /* omada-controller terminates TLS itself (admin UI + device adoption on its
       own static ports), so it needs a server cert of its own rather than hiding
       behind Traefik. Mirrors the daemon cert templates: ONE pkiCert issuance —
       leaf to the destination, matching key via writeToFile — so the pair can
       never mismatch. The public ca_chain read appends intermediate + root, so
       tls.crt is the full leaf→intermediate→root chain omada expects.

       omada-push-kv.sh (the template's exec) then pushes both files into Vault KV;
       the omada-controller Nomad job reads them back and restarts on change. */ -}}
{{- $privateIp := sockaddr "GetPrivateIP" -}}
{{- $ttl := "ttl=720h" -}}
{{- $commonName := "common_name=omada-controller.service.home" -}}
{{- $ipSans := printf "ip_sans=%s" $privateIp -}}
{{- with pkiCert "pki_int_internal/issue/intermediate" $ttl $commonName $ipSans -}}
{{- .Cert -}}
{{- if .Key -}}
{{- .Key | writeToFile "/run/vault-agent/omada-controller/tls.key" "root" "root" "0600" -}}
{{- end -}}
{{- end -}}
{{- with secret "pki_int_internal/cert/ca_chain" -}}
{{- .Data.ca_chain -}}
{{- end -}}
