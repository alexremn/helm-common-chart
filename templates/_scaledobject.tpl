{{/*
=============================================================================
SCALEDOBJECT TEMPLATE
This template renders a KEDA ScaledObject for autoscaling Kubernetes resources.
=============================================================================
*/}}

{{- define "chart.scaledobject" }}
{{- $componentPath := include "common.cmp.valuesKey" .cmp }}
{{- if hasKey .Values $componentPath }}
{{- $componentValues := index .Values $componentPath }}
{{- if $componentValues.scaling }}
{{- if $componentValues.hpa }}
{{- fail (printf "Component '%s' has both .hpa and .scaling set. Pick one — chart.hpa (native HPA) or chart.scaledobject (KEDA)." .cmp) }}
{{- end }}
---
{{- $svc := include "common.appName" . | trim }}
{{- $cmp := include "common.componentName" . | trim }}
{{- $env := include "common.environment" . | trim }}
{{- $scaleConfig := $componentValues.scaling }}
{{- $labelCtx := dict "svc" $svc "cmp" $cmp "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}
{{- /* If pausedReplicaCount is set, fold it into $scaleConfig.annotations BEFORE
       the metadata block emits. Keeps the original whitespace pattern intact
       (common.annotations emits nothing when there are no annotations) so existing
       renders without pausedReplicaCount stay byte-identical. */ -}}
{{- $effectiveAnn := dig "annotations" dict $scaleConfig -}}
{{- if $scaleConfig.pausedReplicaCount -}}
  {{- $effectiveAnn = mergeOverwrite (deepCopy $effectiveAnn) (dict "autoscaling.keda.sh/paused-replicas" (printf "%v" $scaleConfig.pausedReplicaCount)) -}}
{{- end }}

apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: {{ $cmp }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
  {{- $ann := include "common.annotations" (dict "annotations" $effectiveAnn) | trim }}
  {{- if $ann }}
  annotations:
    {{- $ann | nindent 4 }}
  {{- end }}
spec:
  scaleTargetRef:
    name: {{ $cmp }}
    {{- with $scaleConfig.apiVersion }}
    apiVersion: {{ . }}
    {{- end }}
    {{- with $scaleConfig.kind }}
    kind: {{ . }}
    {{- else }}
    kind: Deployment
    {{- end }}
  pollingInterval: {{ default 30 $scaleConfig.pollingInterval }}
  cooldownPeriod: {{ default 180 $scaleConfig.cooldownPeriod }}
  minReplicaCount: {{ default 1 $scaleConfig.min }}
  maxReplicaCount: {{ default 1 $scaleConfig.max }}
  {{- with $scaleConfig.idleReplicaCount }}
  idleReplicaCount: {{ . }}
  {{- end }}
  advanced:
    {{- with $scaleConfig.horizontalPodAutoscalerConfig }}
    horizontalPodAutoscalerConfig: {{ toYaml . | nindent 6 }}
    {{- end }}
    restoreToOriginalReplicaCount: {{ default false $scaleConfig.restoreToOriginalReplicaCount }}
    {{- with $scaleConfig.scalingModifiers }}
    scalingModifiers: {{ toYaml . | nindent 6 }}
    {{- end }}
  fallback:
    failureThreshold: {{ default 3 $scaleConfig.failureThreshold }}
    replicas: {{ default 1 $scaleConfig.fallback }}
  triggers:
  {{- range $scaleConfig.triggers }}
  {{- if eq .type "cron" }}
    - type: cron
      metadata:
        timezone: {{ default "Etc/UTC" .timezone | quote }}
        start: {{ .start | quote }}
        end: {{ .stop | quote }}
        desiredReplicas: {{ .desiredReplicas | quote }}
  {{- else if eq .type "prometheus" }}
    - type: prometheus
      metadata:
        serverAddress: {{ required "scaledObject.triggers[].type=prometheus requires global.prometheusEndpoint to be set" $.Values.global.prometheusEndpoint }}
        threshold: {{ .threshold | quote }}
        {{- /* F2: scope tpl context to Values/Release/Chart + componentValues
               instead of leaking the full chart root via `$`. */}}
        query: {{ tpl .query (dict "Values" $.Values "Release" $.Release "Chart" $.Chart "componentValues" $componentValues) | quote }}
        {{- with .authModes }}
        authModes: {{ . | quote }}
        {{- end }}
        {{- with .unsafeSsl }}
        unsafeSsl: {{ . | quote }}
        {{- end }}
        {{- with .ignoreNullValues }}
        ignoreNullValues: {{ . | quote }}
        {{- end }}
  {{- else if eq .type "redis" }}
    - type: redis
      metadata:
        listName: {{ .listName | quote }}
        listLength: {{ .listLength | quote }}
        addressFromEnv: {{ default "REDIS_HOST" .hostEnv | quote }}
        enableTLS: {{ default "true" .enableTLS }}
        usernameFromEnv: {{ default "REDIS_USERNAME" .usernameEnv | quote }}
        passwordFromEnv: {{ default "REDIS_PASSWORD" .passwordEnv | quote }}
        {{- with .dbIndex }}
        dbIndex: {{ . | quote }}
        {{- end }}
  {{- else if eq .type "cpu" }}
    - type: cpu
      metadata:
        value: {{ .value | quote }}
  {{- else if eq .type "memory" }}
    - type: memory
      metadata:
        value: {{ .value | quote }}
  {{- else if eq .type "kafka" }}
    - type: kafka
      metadata:
        bootstrapServers: {{ .bootstrapServers | quote }}
        consumerGroup: {{ .consumerGroup | quote }}
        topic: {{ .topic | quote }}
        lagThreshold: {{ .lagThreshold | quote }}
        {{- with .offsetResetPolicy }}
        offsetResetPolicy: {{ . | quote }}
        {{- end }}
  {{- else if eq .type "rabbitmq" }}
    - type: rabbitmq
      metadata:
        queueName: {{ .queueName | quote }}
        host: {{ .host | quote }}
        {{- with .queueLength }}
        queueLength: {{ . | quote }}
        {{- end }}
        {{- with .vhostName }}
        vhostName: {{ . | quote }}
        {{- end }}
  {{- else }}
    - type: {{ .type }}
      metadata:
      {{- range $key, $value := .metadata }}
        {{ $key }}: {{ $value | quote }}
      {{- end }}
  {{- end }}
  {{- with .authenticationRef }}
    authenticationRef: {{ toYaml . | nindent 6 }}
  {{- end }}
  {{- with .name }}
    name: {{ . }}
  {{- end }}
  {{- with .metricType }}
    metricType: {{ . }}
  {{- end }}
  {{- with .extraConfig }}
    {{ toYaml . | nindent 6 }}
  {{- end }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}
