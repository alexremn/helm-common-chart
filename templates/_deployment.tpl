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
{{- /* label/render context; canonical shape: common.workload.context.doc */ -}}
{{- $labelCtx := dict "svc" $svc "cmp" $cmp "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}
{{- $values := omit (default dict .Values) }}
{{/*
Resolve the annotation key used for "replicas at first install".
- Explicit override:   .Values.global.deployment.replicasOnCreationAnnotation
- deployTool: werf     werf.io/replicas-on-creation
- deployTool: argocd   empty — ArgoCD has no equivalent; seeding the initial
                       replica count requires Application.spec.ignoreDifferences
                       on /spec/replicas instead
- deployTool: generic  empty
*/}}
{{- $replicasOnCreationAnnotation := dig "global" "deployment" "replicasOnCreationAnnotation" "" $values }}
{{- if eq $replicasOnCreationAnnotation "" }}
  {{- if eq (include "common.deployTool" .) "werf" }}
    {{- $replicasOnCreationAnnotation = "werf.io/replicas-on-creation" }}
  {{- end }}
{{- end }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ $cmp }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
  {{- $emitReplicasAnn := and $replicasOnCreationAnnotation (not $componentValues.replicas) (and ($componentValues.scaling) ($componentValues.scaling.min)) }}
  {{- $extraAnn := dict }}
  {{- if $emitReplicasAnn }}{{- $_ := set $extraAnn $replicasOnCreationAnnotation ($componentValues.scaling.min | toString) }}{{- end }}
  {{- include "common.workload.annotations" (dict "root" . "component" $componentValues "extra" $extraAnn) }}
spec:
  {{- if not (or $componentValues.scaling $componentValues.hpa) }}
  {{- /* Defaults apply only when unset/null: `default`/`with` would also discard an explicit 0. */}}
  replicas: {{ ternary 1 (int $componentValues.replicas) (kindIs "invalid" $componentValues.replicas) }}
  {{- end }}
  {{- /* Rollout keys: <cmp>.<key> > global.deployment.<key> > built-in default.
         The global level is skipped only when unset/null, so a global 0 is kept;
         the component-level checks are unchanged. */}}
  {{- $minReady := $componentValues.minReadySeconds }}
  {{- if kindIs "invalid" $minReady }}{{ $minReady = dig "global" "deployment" "minReadySeconds" nil $values }}{{- end }}
  minReadySeconds: {{ ternary 10 $minReady (kindIs "invalid" $minReady) }}
  {{- if not (kindIs "invalid" $componentValues.revisionHistoryLimit) }}
  revisionHistoryLimit: {{ $componentValues.revisionHistoryLimit }}
  {{- end }}
  {{- /* 0 is not a valid deadline, so at either level it counts as unset. */}}
  {{- with $componentValues.progressDeadlineSeconds | default (dig "global" "deployment" "progressDeadlineSeconds" nil $values) }}
  progressDeadlineSeconds: {{ . }}
  {{- end }}
  {{- with $componentValues.paused }}
  paused: {{ . }}
  {{- end }}
  strategy:
    type: {{ default "RollingUpdate" $componentValues.strategyType }}
    {{- if eq (default "RollingUpdate" $componentValues.strategyType) "RollingUpdate" }}
    rollingUpdate:
      {{- $maxUnavailable := $componentValues.strategyMaxUnavailable | default (dig "global" "deployment" "strategyMaxUnavailable" nil $values) }}
      {{- $maxSurge := $componentValues.strategyMaxSurge | default (dig "global" "deployment" "strategyMaxSurge" nil $values) }}
      maxUnavailable: {{ ternary "25%" $maxUnavailable (kindIs "invalid" $maxUnavailable) }}
      maxSurge: {{ ternary "1" $maxSurge (kindIs "invalid" $maxSurge) }}
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
      {{- include "common.podTemplate.annotations" (dict "configChecksum" $configChecksum "podAnnotations" $podAnn) }}
    spec:
      {{- include "common.workload.podSpec" (merge (dict
        "root" $
        "component" $componentValues
        "svc" $svc
        "cmp" $cmp
        "env" $env
      ) (include "common.workload.fullToggles" . | fromYaml)) | nindent 6 }}
{{- end }}
