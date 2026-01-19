{{- $privateIp := sockaddr "GetPrivateIP" -}}
{{- $prog := "nomad" }}
{{- $commonName := printf "common_name=%s.service.home" $prog -}}
{{- $ipSans := printf "ip_sans=%s" $privateIp -}}
{{- $nomadRole := mustEnv "NOMAD_ROLE" -}}
{{- $altNames := printf "alt_names=%s.global.nomad,localhost" $nomadRole -}}
{{- $ttl := printf "%s" "ttl=32d" -}}
{{- $keyfile := printf "/etc/%s.d/tls.key" $prog -}}
{{- with pkiCert "pki_int_internal/issue/intermediate" $ttl $commonName $ipSans $altNames -}}
{{- .Cert -}}
{{- .CA -}}
{{- if .Key -}}
{{- .Key  | writeToFile $keyfile $prog $prog "0400" -}}
{{- end -}}
{{- end -}}
