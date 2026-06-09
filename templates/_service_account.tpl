{{/*
=============================================================================
SERVICE ACCOUNT TEMPLATE
This template renders a Kubernetes ServiceAccount with annotations.
=============================================================================
*/}}

{{/*
Lowercase canonical alias (matches chart.service / chart.deployment casing).
`chart.serviceAccount` (camelCase) is retained as a deprecated alias for one minor.
*/}}
{{- define "chart.serviceaccount" -}}
{{- include "chart.serviceAccount" . -}}
{{- end -}}

{{- define "chart.serviceAccount" }}
{{- $svc := include "common.appName" . | trim }}
{{- $cmp := include "common.componentName" . | trim }}
{{- $env := include "common.environment" . | trim }}
{{- $componentValues := index .Values (include "common.cmp.valuesKey" .cmp) | default dict }}
{{- $saConfig := $componentValues.serviceAccount | default dict }}
{{- $enabled := dig "enabled" true $saConfig }}
{{- $create := dig "create" true $saConfig }}
{{- if and (ne $enabled false) (ne $create false) }}
---
{{- /* label/render context; canonical shape: common.workload.context.doc */ -}}
{{- $labelCtx := dict "svc" $svc "cmp" $cmp "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}

apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ default $cmp $saConfig.name }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
  {{- $ann := include "common.annotations" $saConfig | trim }}
  {{- if $ann }}
  annotations:
    {{- $ann | nindent 4 }}
  {{- end }}
automountServiceAccountToken: {{ dig "automount" false $saConfig }}
{{- with $saConfig.imagePullSecrets }}
imagePullSecrets: {{ toYaml . | nindent 2 }}
{{- end }}
{{- with $saConfig.secrets }}
secrets: {{ toYaml . | nindent 2 }}
{{- end }}
{{- end }}
{{- end }}
