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
  {{- $minReady := 0 }}
  {{- if hasKey $componentValues "minReadySeconds" }}{{ $minReady = $componentValues.minReadySeconds }}{{- else if hasKey $dsConfig "minReadySeconds" }}{{ $minReady = $dsConfig.minReadySeconds }}{{- end }}
  minReadySeconds: {{ $minReady }}
  {{- $revHist := coalesce $componentValues.revisionHistoryLimit $dsConfig.revisionHistoryLimit }}
  {{- with $revHist }}
  revisionHistoryLimit: {{ . }}
  {{- end }}
  {{- $updStrat := coalesce $componentValues.updateStrategy $dsConfig.updateStrategy }}
  {{- with $updStrat }}
  updateStrategy: {{ toYaml . | nindent 4 }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "common.labels.matchLabels" $labelCtx | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "common.labels" $labelCtx | nindent 8 }}
      {{- $podAnn := include "common.podAnnotations" $componentValues | trim }}
      {{- $configChecksum := include "common.configChecksum" (dict "root" $ "component" $componentValues "cmp" $cmp) | trim }}
      {{- if or $podAnn $configChecksum }}
      annotations:
        {{- with $configChecksum }}
        checksum/config: {{ . }}
        {{- end }}
        {{- with $podAnn }}
        {{- . | nindent 8 }}
        {{- end }}
      {{- end }}
    spec:
      {{- include "common.workload.podSpec" (merge (dict
        "root" $
        "component" $componentValues
        "svc" $svc
        "cmp" $cmp
        "env" $env
      ) (include "common.workload.fullToggles" . | fromYaml)) | nindent 6 }}
{{- end }}
