{{/*
=============================================================================
HTTPROUTE TEMPLATE (Gateway API)
Renders a gateway.networking.k8s.io/v1 HTTPRoute for a component, gated on
`<component>.httpRoute`. The forward-looking complement to chart.ingress for
clusters that have adopted Gateway API (GA since k8s 1.31).

Backend refs default to the component's own Service (common.cmp.dns) on its
`http` port, so a minimal `httpRoute: { parentRefs: [...] }` just works.

Usage: {{ include "chart.httproute" (dict "Values" .Values "Release" .Release "Chart" .Chart "cmp" "web") }}
=============================================================================
*/}}

{{- define "chart.httproute" -}}
{{- $svc := include "common.appName" . | trim }}
{{- $cmp := include "common.componentName" . | trim }}
{{- $env := include "common.environment" . | trim }}
{{- $componentValues := index .Values (include "common.cmp.valuesKey" .cmp) | default dict }}
{{- $hr := $componentValues.httpRoute }}
{{- $labelCtx := dict "svc" $svc "cmp" $cmp "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}
{{- if $hr }}
{{- $svcName := include "common.cmp.dns" $cmp | trim }}
{{- /* Default backend port resolution: <cmp>.httpRoute.port, else the
       component's `http` Service port (int form or {port|containerPort} map),
       else 80. Per-rule `.port` overrides. */ -}}
{{- $defaultPort := 80 }}
{{- $ports := dig "ports" dict $componentValues }}
{{- if and (kindIs "map" $ports) (hasKey $ports "http") }}
  {{- $http := index $ports "http" }}
  {{- if kindIs "map" $http }}{{- $defaultPort = (coalesce $http.port $http.containerPort 80) }}{{- else }}{{- $defaultPort = $http }}{{- end }}
{{- end }}
{{- $defaultPort = int (dig "port" $defaultPort $hr) }}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ $cmp }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
  {{- with $hr.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  {{- with $hr.parentRefs }}
  parentRefs:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $hr.hostnames }}
  hostnames:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  rules:
  {{- if $hr.rules }}
  {{- range $hr.rules }}
    -
      {{- with .matches }}
      matches:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .filters }}
      filters:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      backendRefs:
      {{- if .backendRefs }}
        {{- toYaml .backendRefs | nindent 8 }}
      {{- else }}
        - name: {{ $svcName }}
          port: {{ int (default $defaultPort .port) }}
      {{- end }}
  {{- end }}
  {{- else }}
    - backendRefs:
        - name: {{ $svcName }}
          port: {{ $defaultPort }}
  {{- end }}
{{- end }}
{{- end -}}
