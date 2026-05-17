{{/*
=============================================================================
JOB TEMPLATE
This template renders a Kubernetes Job with common configuration.
=============================================================================
*/}}

{{- define "chart.job" }}
---
{{- $svc := include "common.appName" . | trim }}
{{- $cmp := include "common.componentName" . | trim }}
{{- $env := include "common.environment" . | trim }}
{{- $componentValues := index .Values.jobs (include "common.cmp.valuesKey" .cmp) | default dict }}
{{- $labelCtx := dict "svc" $svc "cmp" $cmp "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}

apiVersion: batch/v1
kind: Job
metadata:
  name: {{ $cmp }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
  {{- $ann := include "common.annotations" $componentValues | trim }}
  {{- if $ann }}
  annotations:
    {{- $ann | nindent 2 }}
  {{- end }}
spec:
  backoffLimit: {{ default 0 $componentValues.backoffLimit | int }}
  {{- with $componentValues.activeDeadlineSeconds }}
  activeDeadlineSeconds: {{ . }}
  {{- end }}
  {{- with $componentValues.ttlSecondsAfterFinished }}
  ttlSecondsAfterFinished: {{ . }}
  {{- end }}
  {{- with $componentValues.completions }}
  completions: {{ . }}
  {{- end }}
  {{- with $componentValues.parallelism }}
  parallelism: {{ . }}
  {{- end }}
  {{- with $componentValues.completionMode }}
  completionMode: {{ . }}
  {{- end }}
  {{- with $componentValues.podFailurePolicy }}
  podFailurePolicy: {{ toYaml . | nindent 4 }}
  {{- end }}
  {{- with $componentValues.suspend }}
  suspend: {{ . }}
  {{- end }}
  {{- with $componentValues.manualSelector }}
  manualSelector: {{ . }}
  {{- end }}
  {{- with $componentValues.selector }}
  selector: {{ toYaml . | nindent 4 }}
  {{- end }}
  template:
    metadata:
      labels:
        {{- include "common.labels" $labelCtx | nindent 8 }}
      {{- $podAnn := include "common.podAnnotations" $componentValues | trim }}
      {{- if $podAnn }}
      annotations:
        {{- $podAnn | nindent 2 }}
      {{- end }}
    spec:
      {{- include "common.workload.podSpec" (dict
        "root" $
        "component" $componentValues
        "svc" $svc
        "cmp" $cmp
        "env" $env
        "includePriorityClassName" true
        "restartPolicy" (default "Never" $componentValues.restartPolicy)
      ) | nindent 6 }}
{{- end }}
