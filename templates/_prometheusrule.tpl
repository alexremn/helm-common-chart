{{/*
=============================================================================
PROMETHEUSRULE TEMPLATE
Renders one PrometheusRule per entry in .Values.prometheusRules. The
Prometheus Operator must be installed in the cluster.

Usage: {{ include "chart.prometheusrule" (dict "Values" .Values "Release" .Release "Chart" .Chart "cmp" "web") }}
=============================================================================
*/}}

{{- define "chart.prometheusrule" }}
{{- $svc := include "common.appName" . | trim }}
{{- $env := include "common.environment" . | trim }}
{{- /* Top-level passthrough: object name is the verbatim consumer key, so do
       NOT stamp a component label these namespace-shared resources don't own. */ -}}
{{- $labelCtx := dict "svc" $svc "cmp" "" "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}
{{- $values := include "common._values" . | fromYaml | default dict }}
{{- range $name, $val := dig "prometheusRules" dict $values }}
---
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: {{ $name }}
  labels:
    {{ include "common.labels" $labelCtx | nindent 4 }}
    {{- with (dig "global" "monitoring" "releaseLabel" "" $values) }}
    release: {{ . }}
    {{- end }}
    {{- with $val.labels }}
    {{ toYaml . | nindent 4 }}
    {{- end }}
  {{- with $val.annotations }}
  annotations: {{ toYaml . | nindent 4 }}
  {{- end }}
spec:
  groups: {{ toYaml (required (printf "prometheusRules entry %q must define groups" $name) $val.groups) | nindent 4 }}
{{- end }}
{{- end }}
