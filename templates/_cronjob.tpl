{{/*
=============================================================================
CRONJOB TEMPLATE
This template renders a Kubernetes CronJob with standard configuration.
=============================================================================
*/}}

{{- define "chart.cronjob" -}}
---
{{- $svc := include "common.appName" . | trim }}
{{- $cmp := include "common.componentName" . | trim }}
{{- $env := include "common.environment" . | trim }}
{{- $componentValues := index .Values.cronjobs (include "common.cmp.valuesKey" .cmp) | default dict }}
{{- $labelCtx := dict "svc" $svc "cmp" $cmp "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}

apiVersion: batch/v1
kind: CronJob
metadata:
  name: {{ $cmp }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
  {{- include "common.workload.annotations" (dict "root" . "component" $componentValues) }}
spec:
  schedule: {{ (required "Schedule expression is required" $componentValues.schedule) | quote }}
  concurrencyPolicy: {{ default "Forbid" $componentValues.concurrencyPolicy | quote }}
  successfulJobsHistoryLimit: {{ default 1 $componentValues.successfulJobsHistoryLimit | int }}
  failedJobsHistoryLimit: {{ default 1 $componentValues.failedJobsHistoryLimit | int }}
  {{- with $componentValues.startingDeadlineSeconds }}
  startingDeadlineSeconds: {{ . }}
  {{- end }}
  {{- with $componentValues.suspend }}
  suspend: {{ . }}
  {{- end }}
  {{- with $componentValues.timeZone }}
  timeZone: {{ . | quote }}
  {{- end }}
  jobTemplate:
    spec:
      {{- with $componentValues.activeDeadlineSeconds }}
      activeDeadlineSeconds: {{ . }}
      {{- end }}
      backoffLimit: {{ default 0 $componentValues.backoffLimit | int }}
      {{- with $componentValues.ttlSecondsAfterFinished }}
      ttlSecondsAfterFinished: {{ . }}
      {{- end }}
      {{- with $componentValues.podFailurePolicy }}
      podFailurePolicy: {{ toYaml . | nindent 8 }}
      {{- end }}
      template:
        metadata:
          labels:
            {{- include "common.labels" $labelCtx | nindent 12 }}
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
            "restartPolicy" (default "Never" $componentValues.restartPolicy)
          ) | nindent 10 }}
{{- end -}}
