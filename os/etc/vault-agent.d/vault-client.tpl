{{- $privateIp := sockaddr "GetPrivateIP" -}}
{{- $prog := "vault" }}
{{- $hostname := mustEnv "HOSTNAME" -}}
{{- $commonName := printf "common_name=%s" $hostname -}}
{{- $ipSans := printf "ip_sans=%s" $privateIp -}}
{{- $ttl := "ttl=32d" -}}
{{- $altNames := "alt_names=vault.service.home" -}}
{{- $keyfile := "/etc/vault.d/private/client.key" -}}
{{- with pkiCert "pki_int_internal/issue/intermediate" $ttl $commonName $ipSans $altNames -}}
{{- .Cert -}}
{{- .CA -}}
{{- if .Key -}}
{{- .Key  | writeToFile $keyfile $prog $prog "0400" -}}
{{- end -}}
{{- end -}}
