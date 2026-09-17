{{/*
=============================================================================
HTTPROUTE TEMPLATE (Gateway API)
Renders a gateway.networking.k8s.io/v1 HTTPRoute for a component, gated on
`<component>.httpRoute` and/or `<component>.httpRoutes`. The forward-looking
complement to chart.ingress for clusters that have adopted Gateway API (GA
since k8s 1.31).

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
{{- $httpRoutes := $componentValues.httpRoutes }}
{{- $labelCtx := dict "svc" $svc "cmp" $cmp "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}
{{- $svcName := include "common.cmp.dns" $cmp | trim }}
{{- /* Default backend port resolution: <cmp>.httpRoute.port, else the
       component's `http` SERVICE port, else 80. Per-rule `.port` overrides.
       Resolved through common.ports.servicePort so this always matches what
       chart.service exposes - a backendRef naming a port the Service does not
       have still reports ResolvedRefs=True, so drift here fails silently. */ -}}
{{- $basePort := 80 }}
{{- $ports := dig "ports" dict $componentValues }}
{{- if and (kindIs "map" $ports) (hasKey $ports "http") }}
  {{- $resolved := include "common.ports.servicePort" (dict "port" (index $ports "http")) }}
  {{- if $resolved }}{{- $basePort = $resolved }}{{- end }}
{{- end }}
{{- $entries := list }}
{{- if $hr }}
{{- $entries = append $entries (dict "name" $cmp "hr" $hr) }}
{{- end }}
{{- if kindIs "map" $httpRoutes }}
{{- range $name, $entryHr := $httpRoutes }}
{{- if $entryHr }}
{{- $entries = append $entries (dict "name" (include "common.cmp.dns" (printf "%s-%s-httproute" $cmp $name) | trim) "hr" $entryHr) }}
{{- end }}
{{- end }}
{{- end }}
{{- range $entries }}
{{- $name := .name }}
{{- $entryHr := .hr }}
{{- $defaultPort := int (dig "port" $basePort $entryHr) }}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ $name }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
  {{- with $entryHr.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  {{- with $entryHr.parentRefs }}
  parentRefs:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $entryHr.hostnames }}
  hostnames:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- include "common.httproute.rules" (dict "hr" $entryHr "svcName" $svcName "defaultPort" $defaultPort) | nindent 2 }}
{{- end }}
{{- end -}}
