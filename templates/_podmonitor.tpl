{{/*
=============================================================================
PODMONITOR TEMPLATES
This file contains templates for Prometheus Operator PodMonitor resources.
=============================================================================
*/}}

{{/*
Handle port selection for podMonitor
Uses explicit configuration if available, otherwise tries to smartly select a port
*/}}
{{- define "podMonitor.getMetricsPort" -}}
{{- $componentValues := . }}
{{- $default := "metrics" }}
{{- $resolved := "" }}
{{- if and $componentValues.podMonitor $componentValues.podMonitor.portName }}
  {{- $resolved = $componentValues.podMonitor.portName }}
{{- else if and $componentValues.ports (hasKey $componentValues.ports "metrics") }}
  {{- $resolved = $default }}
{{- else if and $componentValues.ports (hasKey $componentValues.ports "prometheus") }}
  {{- $resolved = "prometheus" }}
{{- else if $componentValues.ports }}
  {{- $resolved = keys $componentValues.ports | sortAlpha | first }}
{{- else }}
  {{- $resolved = $default }}
{{- end }}
{{- /* If the component declares ports, the resolved name MUST be one of
       them — otherwise the PodMonitor is silently broken (Prometheus
       sees a "target down" but the chart accepts the resource). */ -}}
{{- if and $componentValues.ports (not (hasKey $componentValues.ports $resolved)) }}
  {{- fail (printf "podMonitor: resolved port name %q not in component ports %v. Set podMonitor.portName to one of the listed names." $resolved (keys $componentValues.ports | sortAlpha)) }}
{{- end }}
{{ $resolved }}
{{- end -}}

{{/*
Handle path selection for podMonitor
*/}}
{{- define "podMonitor.getMetricsPath" -}}
{{- $componentValues := . }}
{{- if and $componentValues.podMonitor $componentValues.podMonitor.path }}
{{ $componentValues.podMonitor.path }}
{{- else }}
{{ "/metrics" }}
{{- end }}
{{- end -}}

{{/*
Main PodMonitor template
*/}}
{{- define "chart.podmonitor" }}
{{- $svc := include "common.appName" . | trim }}
{{- $cmp := include "common.componentName" . | trim }}
{{- $env := include "common.environment" . | trim }}
{{- $componentValues := index .Values (include "common.cmp.valuesKey" .cmp) | default dict }}
{{- $pmConfig := $componentValues.podMonitor | default dict }}
{{- if and $pmConfig (ne (dig "enabled" true $pmConfig) false) }}
{{- if and $componentValues.serviceMonitor (ne (dig "enabled" true $componentValues.serviceMonitor) false) }}
{{- fail (printf "Component '%s' has both podMonitor and serviceMonitor enabled — pick one." $cmp) }}
{{- end }}
---
{{- $labelCtx := dict "svc" $svc "cmp" $cmp "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}

apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: {{ $cmp }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
  {{- with $componentValues.podMonitor.labels }}
    {{ toYaml . | nindent 4 }}
  {{- end }}
  {{- $ann := include "common.annotations" $pmConfig | trim }}
  {{- if $ann }}
  annotations:
    {{- $ann | nindent 2 }}
  {{- end }}
spec:
  selector:
    matchLabels:
      {{- include "common.labels.matchLabels" $labelCtx | nindent 6 }}
    {{- with $componentValues.podMonitor.selectorMatchLabels }}
      {{ toYaml . | nindent 6 }}
    {{- end }}
  podMetricsEndpoints:
  {{- if $componentValues.podMonitor.endpoints }}
  {{- range $endpoint := $componentValues.podMonitor.endpoints }}
    - {{- with $endpoint.filterRunning }}
      filterRunning: {{ . }}
      {{- end }}
      {{- with $endpoint.followRedirects }}
      followRedirects: {{ . }}
      {{- end }}
      interval: {{ default "1m" $endpoint.interval }}
      path: {{ default "/metrics" $endpoint.path }}
      port: {{ required "podMonitor endpoint requires a port name" $endpoint.port | quote }}
      {{- with $endpoint.scheme }}
      scheme: {{ . }}
      {{- end }}
      {{- with $endpoint.scrapeTimeout }}
      scrapeTimeout: {{ . }}
      {{- end }}
      {{- with $endpoint.honorLabels }}
      honorLabels: {{ . }}
      {{- end }}
      {{- with $endpoint.honorTimestamps }}
      honorTimestamps: {{ . }}
      {{- end }}
      {{- with $endpoint.metricRelabelings }}
      metricRelabelings: {{ toYaml . | nindent 8 }}
      {{- end }}
      {{- with $endpoint.relabelings }}
      relabelings: {{ toYaml . | nindent 8 }}
      {{- end }}
      {{- with $endpoint.tlsConfig }}
      tlsConfig: {{ toYaml . | nindent 8 }}
      {{- end }}
  {{- end }}
  {{- else }}
    - filterRunning: {{ default true $componentValues.podMonitor.filterRunning }}
      followRedirects: {{ default true $componentValues.podMonitor.followRedirects }}
      interval: {{ default "1m" $componentValues.podMonitor.interval }}
      path: {{ include "podMonitor.getMetricsPath" $componentValues | trim }}
      port: {{ include "podMonitor.getMetricsPort" $componentValues | trim | quote }}
      {{- with $componentValues.podMonitor.scheme }}
      scheme: {{ . }}
      {{- end }}
      {{- with $componentValues.podMonitor.scrapeTimeout }}
      scrapeTimeout: {{ . }}
      {{- end }}
      {{- with $componentValues.podMonitor.honorLabels }}
      honorLabels: {{ . }}
      {{- end }}
      {{- with $componentValues.podMonitor.honorTimestamps }}
      honorTimestamps: {{ . }}
      {{- end }}
      {{- /* Profile metricRelabelings are stored as a verbatim YAML string
             (see common.profile.defaults) so the rails default emits byte-identically
             to the v1.3.1 hardcoded text. Empty string under generic/python/go means
             no default metricRelabelings are emitted. */ -}}
      {{- $profileRelabelings := index (include "common.profile.defaults" $ | fromYaml) (include "common.profile" $) "podMonitor" "metricRelabelings" -}}
      {{- include "common.prometheus.metricRelabelings" (dict "explicit" $componentValues.podMonitor.metricRelabelings "profile" $profileRelabelings) }}
      {{- with $componentValues.podMonitor.relabelings }}
      relabelings: {{ toYaml . | nindent 8 }}
      {{- end }}
      {{- with $componentValues.podMonitor.tlsConfig }}
      tlsConfig: {{ toYaml . | nindent 8 }}
      {{- end }}
  {{- end }}
  namespaceSelector:
    {{- with $componentValues.podMonitor.namespaceSelector }}
      {{ toYaml . | nindent 4 }}
    {{- else }}
    matchNames:
      - {{ $.Release.Namespace }}
    {{- end }}
  {{- with $componentValues.podMonitor.attachMetadata }}
  attachMetadata: {{ toYaml . | nindent 4 }}
  {{- end }}
  {{- with $componentValues.podMonitor.sampleLimit }}
  sampleLimit: {{ . }}
  {{- end }}
  {{- with $componentValues.podMonitor.targetLimit }}
  targetLimit: {{ . }}
  {{- end }}
  {{- with $componentValues.podMonitor.labelLimit }}
  labelLimit: {{ . }}
  {{- end }}
  {{- with $componentValues.podMonitor.labelNameLengthLimit }}
  labelNameLengthLimit: {{ . }}
  {{- end }}
  {{- with $componentValues.podMonitor.labelValueLengthLimit }}
  labelValueLengthLimit: {{ . }}
  {{- end }}
  {{- with $componentValues.podMonitor.jobLabel }}
  jobLabel: {{ . }}
  {{- end }}
  {{- with $componentValues.podMonitor.podTargetLabels }}
  podTargetLabels: {{ toYaml . | nindent 4 }}
  {{- end }}
  {{- with $componentValues.podMonitor.extraConfig }}
    {{ toYaml . | nindent 2 }}
  {{- end }}
{{- end -}}
{{- end -}}
