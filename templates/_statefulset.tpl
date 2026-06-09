{{- define "chart.statefulset" }}
---
{{- $svc := include "common.appName" . | trim }}
{{- $cmp := include "common.componentName" . | trim }}
{{- $env := include "common.environment" . | trim }}
{{- $componentValues := index .Values (include "common.cmp.valuesKey" .cmp) | default dict }}
{{- /* label/render context; canonical shape: common.workload.context.doc */ -}}
{{- $labelCtx := dict "svc" $svc "cmp" (include "common.safeName" (dict "name" $cmp) | trim) "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {{ include "common.safeName" (dict "name" $cmp) | trim }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
  {{- include "common.workload.annotations" (dict "root" . "component" $componentValues) }}
spec:
  serviceName: {{ default (printf "%s-headless" (include "common.safeName" (dict "name" $cmp "maxLength" 54) | trim)) $componentValues.serviceName | quote }}
  updateStrategy:
    type: {{ default "RollingUpdate" $componentValues.updateStrategy | quote }}
  podManagementPolicy: {{ default "OrderedReady" $componentValues.podManagementPolicy | quote }}
  minReadySeconds: {{ default 0 $componentValues.minReadySeconds }}
  {{- if not (or $componentValues.scaling $componentValues.hpa) }}
  replicas: {{ default 1 $componentValues.replicas | int }}
  {{- end }}
  {{- with $componentValues.revisionHistoryLimit }}
  revisionHistoryLimit: {{ . }}
  {{- end }}
  {{- with $componentValues.persistentVolumeClaimRetentionPolicy }}
  persistentVolumeClaimRetentionPolicy: {{ toYaml . | nindent 4 }}
  {{- end }}
  {{- with $componentValues.ordinals }}
  ordinals: {{ toYaml . | nindent 4 }}
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
  {{- with $componentValues.persistence }}
  volumeClaimTemplates:
    {{- if kindIs "map" . }}
    - metadata:
        name: {{ default "data" .name }}
        labels:
          {{- include "common.labels" $labelCtx | nindent 10 }}
        {{- with .annotations }}
        annotations: {{ toYaml . | nindent 10 }}
        {{- end }}
      spec: {{ include "common.pvc.spec" . | nindent 8 }}
    {{- else if kindIs "slice" . }}
    {{- range $vol := . }}
    - metadata:
        name: {{ required "Volume name is required" $vol.name }}
        labels:
          {{- include "common.labels" $labelCtx | nindent 10 }}
        {{- with $vol.annotations }}
        annotations: {{ toYaml . | nindent 10 }}
        {{- end }}
      spec: {{ include "common.pvc.spec" $vol | nindent 8 }}
    {{- end }}
    {{- end }}
  {{- end }}
{{- end }}
