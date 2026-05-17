{{/*
=============================================================================
DEPLOYMENT TEMPLATE
This template renders a standard Kubernetes Deployment with common boilerplate,
security contexts, probes, etc.
=============================================================================
*/}}

{{- define "chart.deployment" }}
---
{{- $svc := include "common.appName" . | trim }}
{{- $cmp := include "common.componentName" . | trim }}
{{- $env := include "common.environment" . | trim }}
{{- $componentValues := index .Values (include "common.cmp.valuesKey" .cmp) | default dict }}
{{- $labelCtx := dict "svc" $svc "cmp" $cmp "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}
{{- $values := include "common._values" . | fromYaml | default dict }}
{{/*
Resolve the annotation key used for "replicas at first install".
- Explicit override:   .Values.global.deployment.replicasOnCreationAnnotation
- Werf compatibility:  emits werf.io/replicas-on-creation when werf annotations
                       are enabled (see common.werf.annotationsEnabled)
- Otherwise:           empty (annotation skipped)
*/}}
{{- $replicasOnCreationAnnotation := dig "global" "deployment" "replicasOnCreationAnnotation" "" $values }}
{{- if eq $replicasOnCreationAnnotation "" }}
  {{- if eq (include "common.werf.annotationsEnabled" .) "true" }}
    {{- $replicasOnCreationAnnotation = "werf.io/replicas-on-creation" }}
  {{- end }}
{{- end }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ $cmp }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
  {{- $werfAnn := include "common.annotations.werf" . | trim }}
  {{- $userAnn := $componentValues.annotations }}
  {{- $emitReplicasAnn := and $replicasOnCreationAnnotation (not $componentValues.replicas) (and ($componentValues.scaling) ($componentValues.scaling.min)) }}
  {{- if or $werfAnn $userAnn $emitReplicasAnn }}
  annotations:
    {{- if $werfAnn }}
    {{- $werfAnn | nindent 4 }}
    {{- end }}
    {{- with $userAnn }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
    {{- if $emitReplicasAnn }}
    {{ printf "%s: %s" $replicasOnCreationAnnotation ($componentValues.scaling.min | quote) }}
    {{- end }}
  {{- end }}
spec:
  {{- if not $componentValues.scaling }}
  replicas: {{ default 1 $componentValues.replicas | int }}
  {{- end }}
  minReadySeconds: {{ default 10 $componentValues.minReadySeconds }}
  {{- with $componentValues.revisionHistoryLimit }}
  revisionHistoryLimit: {{ . }}
  {{- end }}
  {{- with $componentValues.progressDeadlineSeconds }}
  progressDeadlineSeconds: {{ . }}
  {{- end }}
  {{- with $componentValues.paused }}
  paused: {{ . }}
  {{- end }}
  strategy:
    type: {{ default "RollingUpdate" $componentValues.strategyType }}
    {{- if eq (default "RollingUpdate" $componentValues.strategyType) "RollingUpdate" }}
    rollingUpdate:
      maxUnavailable: {{ default "25%" $componentValues.strategyMaxUnavailable }}
      maxSurge: {{ default "1" $componentValues.strategyMaxSurge }}
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
