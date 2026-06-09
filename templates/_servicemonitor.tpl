{{/*
=============================================================================
SERVICEMONITOR TEMPLATE
Renders a Prometheus Operator ServiceMonitor scoped to the component's
Service. Mutually exclusive with chart.podmonitor on the same component —
both helpers fail fast if the component has both .podMonitor and
.serviceMonitor enabled.
=============================================================================
*/}}

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
{{- $profileRelabelings := index (include "common.profile.defaults" $ | fromYaml) (include "common.profile" (dict "root" $ "component" $componentValues)) "podMonitor" "metricRelabelings" }}
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{ $cmp }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
    {{- with (dig "global" "monitoring" "releaseLabel" "" (toYaml .Values | fromYaml)) }}
    release: {{ . }}
    {{- end }}
    {{- with $sm.labels }}
    {{- toYaml . | nindent 4 }}
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
  {{- if hasKey $sm "namespaceSelector" }}
  namespaceSelector: {{ toYaml $sm.namespaceSelector | nindent 4 }}
  {{- else }}
  namespaceSelector:
    matchNames:
      - {{ $.Release.Namespace }}
  {{- end }}
{{- end }}
{{- end }}
