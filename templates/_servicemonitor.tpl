{{/*
=============================================================================
SERVICEMONITOR TEMPLATE
Renders a Prometheus Operator ServiceMonitor scoped to the component's
Service. Mutually exclusive with chart.podmonitor on the same component —
both helpers fail fast if the component has both .podMonitor and
.serviceMonitor enabled.
=============================================================================
*/}}

{{/*
Render the metricRelabelings block (with profile fallback) of a
ServiceMonitor or PodMonitor endpoint. Identical logic for both kinds.

Emits nothing when both explicit and profile are empty.

Usage (must be invoked with `{{- ... -}}` whitespace trimming):
  {{- include "common.prometheus.metricRelabelings" (dict
        "explicit" $cfg.metricRelabelings
        "profile" $profileRelabelings) -}}
*/}}
{{- define "common.prometheus.metricRelabelings" -}}
{{- $explicit := .explicit -}}
{{- $profile := .profile -}}
{{- if $explicit }}
      metricRelabelings: {{ toYaml $explicit | nindent 8 }}
{{- else if $profile }}
      metricRelabelings:
{{ $profile | indent 8 }}
{{- end -}}
{{- end -}}

{{- define "chart.servicemonitor" }}
{{- $svc := include "common.appName" . | trim }}
{{- $cmp := include "common.componentName" . | trim }}
{{- $env := include "common.environment" . | trim }}
{{- $componentValues := index .Values (include "common.cmp.valuesKey" .cmp) | default dict }}
{{- $sm := $componentValues.serviceMonitor | default dict }}
{{- if and $sm (ne (dig "enabled" true $sm) false) }}
{{- if and $componentValues.podMonitor (ne (dig "enabled" true $componentValues.podMonitor) false) }}
{{- fail (printf "Component '%s' has both podMonitor and serviceMonitor enabled — pick one." $cmp) }}
{{- end }}
{{- $labelCtx := dict "svc" $svc "cmp" $cmp "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}
{{- $profileRelabelings := index (include "common.profile.defaults" $ | fromYaml) (include "common.profile" $) "podMonitor" "metricRelabelings" }}
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{ $cmp }}
  labels:
    {{ include "common.labels" $labelCtx | nindent 4 }}
    {{- with $sm.labels }}
    {{ toYaml . | nindent 4 }}
    {{- end }}
  {{- with $sm.annotations }}
  annotations: {{ toYaml . | nindent 4 }}
  {{- end }}
spec:
  selector:
    matchLabels:
      {{- include "common.labels.matchLabels" $labelCtx | nindent 6 }}
  endpoints:
    - port: {{ required "serviceMonitor.portName is required" $sm.portName | quote }}
      path: {{ default "/metrics" $sm.path }}
      interval: {{ default "30s" $sm.interval }}
      {{- with $sm.scrapeTimeout }}
      scrapeTimeout: {{ . }}
      {{- end }}
      {{- with $sm.scheme }}
      scheme: {{ . }}
      {{- end }}
      {{- with $sm.honorLabels }}
      honorLabels: {{ . }}
      {{- end }}
      {{- include "common.prometheus.metricRelabelings" (dict "explicit" $sm.metricRelabelings "profile" $profileRelabelings) }}
      {{- with $sm.relabelings }}
      relabelings: {{ toYaml . | nindent 8 }}
      {{- end }}
  {{- with $sm.targetLabels }}
  targetLabels: {{ toYaml . | nindent 4 }}
  {{- end }}
  {{- with $sm.namespaceSelector }}
  namespaceSelector: {{ toYaml . | nindent 4 }}
  {{- else }}
  namespaceSelector:
    matchNames:
      - {{ $.Release.Namespace }}
  {{- end }}
{{- end }}
{{- end }}
