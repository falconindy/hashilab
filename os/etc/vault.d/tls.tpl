{{- $privateIp := sockaddr "GetPrivateIP" -}}
{{- $prog := "vault" }}
{{- $commonName := printf "common_name=%s.service.home" $prog -}}
{{- $ipSans := printf "ip_sans=%s" $privateIp -}}
{{- $altNames := printf "alt_names=active.vault.service.home,standby.vault.service.home,localhost" -}}
{{- $ttl := printf "%s" "ttl=32d" -}}
{{- $keyfile := printf "/etc/%s.d/tls.key" $prog -}}
{{- with pkiCert "pki_int_internal/issue/intermediate" $ttl $commonName $ipSans $altNames -}}
{{- .Cert -}}
{{- .CA -}}
{{- if .Key -}}
{{- .Key  | writeToFile $keyfile $prog $prog "0400" -}}
{{- end -}}
{{- end -}}
