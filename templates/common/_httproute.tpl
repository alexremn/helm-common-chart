{{/*
Name of the HTTPRoute of an `httpRoutes` entry. One definition for chart.httproute,
which renders it, and chart.agentgatewaypolicy, which targets it by that name.
Expects:
- .cmp: the component name
- .key: the entry's key in httpRoutes
*/}}
{{- define "common.httproute.entryName" -}}
{{- include "common.cmp.dns" (printf "%s-%s-httproute" .cmp .key) -}}
{{- end -}}

{{/*
Render the rules of an HTTPRoute.
Expects:
- .hr: the route spec (httpRoute or an httpRoutes entry)
- .svcName: default backend Service name
- .defaultPort: default backend port
*/}}
{{- define "common.httproute.rules" -}}
{{- $hr := .hr }}
{{- $svcName := .svcName }}
{{- $defaultPort := .defaultPort }}
rules:
{{- if $hr.rules }}
{{- range $hr.rules }}
  -
    {{- with .name }}
    name: {{ . | quote }}
    {{- end }}
    {{- with .matches }}
    matches:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .filters }}
    filters:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- $hasRedirect := false }}
    {{- range .filters }}
    {{- if eq .type "RequestRedirect" }}{{- $hasRedirect = true }}{{- end }}
    {{- end }}
    {{- if not $hasRedirect }}
    backendRefs:
    {{- if .backendRefs }}
      {{- toYaml .backendRefs | nindent 6 }}
    {{- else }}
      - name: {{ $svcName }}
        port: {{ int (default $defaultPort .port) }}
    {{- end }}
    {{- end }}
    {{- with .timeouts }}
    timeouts:
      {{- toYaml . | nindent 6 }}
    {{- end }}
{{- end }}
{{- else }}
  - backendRefs:
      - name: {{ $svcName }}
        port: {{ $defaultPort }}
{{- end }}
{{- end -}}
