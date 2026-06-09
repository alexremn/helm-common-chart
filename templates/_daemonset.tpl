{{/*
=============================================================================
DAEMONSET TEMPLATE
Renders a DaemonSet using the same pod spec helpers as Deployment/StatefulSet.
=============================================================================
*/}}

{{- define "chart.daemonset" }}
---
{{- $svc := include "common.appName" . | trim }}
{{- $cmp := include "common.componentName" . | trim }}
{{- $env := include "common.environment" . | trim }}
{{- $componentValues := index .Values (include "common.cmp.valuesKey" .cmp) | default dict }}
{{- $dsConfig := dig "daemonSet" dict $componentValues }}
{{- /* label/render context; canonical shape: common.workload.context.doc */ -}}
{{- $labelCtx := dict "svc" $svc "cmp" $cmp "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: {{ $cmp }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
  {{- include "common.workload.annotations" (dict "root" . "component" $componentValues) }}
spec:
  {{- if hasKey $dsConfig "minReadySeconds" }}
  minReadySeconds: {{ $dsConfig.minReadySeconds }}
  {{- else if hasKey $componentValues "minReadySeconds" }}
  minReadySeconds: {{ $componentValues.minReadySeconds }}
  {{- else }}
  minReadySeconds: 0
  {{- end }}
  {{- with $dsConfig.revisionHistoryLimit }}
  revisionHistoryLimit: {{ . }}
  {{- end }}
  {{- with $dsConfig.updateStrategy }}
  updateStrategy: {{ toYaml . | nindent 4 }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "common.labels.matchLabels" $labelCtx | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "common.labels" $labelCtx | nindent 8 }}
      {{- with $componentValues.podAnnotations }}
      annotations: {{ toYaml . | nindent 8 }}
      {{- end }}
    spec:
      {{- include "common.workload.podSpec" (dict
        "root" $
        "component" $componentValues
        "svc" $svc
        "cmp" $cmp
        "env" $env
        "includePorts" true
        "includeProbes" true
        "includeLifecycle" true
        "includePriorityClassName" true
        "includeHostAliases" true
        "includeTopologySpreadConstraints" true
        "includeTerminationGracePeriod" true
      ) | nindent 6 }}
{{- end }}
