{{- $privateIp := sockaddr "GetPrivateIP" -}}
{{- $prog := "vault" }}
{{- $commonName := printf "common_name=%s.service.home" $prog -}}
{{- $ipSans := printf "ip_sans=127.0.0.1,%s" $privateIp -}}
{{- $altNames := printf "alt_names=active.vault.service.home,standby.vault.service.home,localhost" -}}
{{- $ttl := printf "%s" "ttl=32d" -}}
{{- $keyfile := printf "/etc/%s.d/server.key" $prog -}}
{{- with pkiCert "pki_int_internal/issue/servers" $ttl $commonName $ipSans $altNames -}}
{{- .Cert -}}
{{- .CA -}}
{{- if .Key -}}
{{- .Key  | writeToFile $keyfile $prog $prog "0400" -}}
{{- end -}}
{{- end -}}
