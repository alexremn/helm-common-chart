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
{{- /* label/render context; canonical shape: common.workload.context.doc */ -}}
{{- $labelCtx := dict "svc" $svc "cmp" $cmp "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}

apiVersion: batch/v1
kind: Job
metadata:
  name: {{ $cmp }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
  {{- /* Under ArgoCD a Job is an ordinary tracked resource: its spec.template
         is immutable, so the first change fails the apply, and when nothing
         changed the completed Job already matches desired state and never
         re-runs. An ArgoCD hook with BeforeHookCreation fixes both. */ -}}
  {{- $jobExtra := dict }}
  {{- $hook := dig "hook" "" $componentValues }}
  {{- if and $hook (ne $hook "Skip") (eq (include "common.deployTool" .) "argocd") }}
  {{- $valid := list "PreSync" "Sync" "PostSync" "Skip" }}
  {{- if not (has $hook $valid) }}
  {{- fail (printf "Unknown jobs.%s.hook %q. Valid values: %s." $cmp $hook (join ", " $valid)) }}
  {{- end }}
  {{- $_ := set $jobExtra "argocd.argoproj.io/hook" $hook }}
  {{- $_ := set $jobExtra "argocd.argoproj.io/hook-delete-policy" (dig "hookDeletePolicy" "BeforeHookCreation" $componentValues) }}
  {{- end }}
  {{- include "common.workload.annotations" (dict "root" . "component" $componentValues "extra" $jobExtra) }}
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
        {{- $podAnn | nindent 8 }}
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
