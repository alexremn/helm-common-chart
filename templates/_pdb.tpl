{{/*
=============================================================================
POD DISRUPTION BUDGET TEMPLATE
This template renders a Kubernetes PodDisruptionBudget to manage disruptions
during voluntary disruptions like upgrades.
=============================================================================
*/}}

{{- define "chart.pdb" }}
---
{{- $svc := include "common.appName" . | trim }}
{{- $cmp := include "common.componentName" . | trim }}
{{- $env := include "common.environment" . | trim }}
{{- $componentValues := index .Values (include "common.cmp.valuesKey" .cmp) | default dict }}
{{- $pdbConfig := $componentValues.pdb | default dict }}
{{- $values := include "common._values" . | fromYaml | default dict }}
{{- $labelCtx := dict "svc" $svc "cmp" $cmp "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}

apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ $cmp }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
  {{- $ann := include "common.annotations" $pdbConfig | trim }}
  {{- if $ann }}
  annotations:
    {{- $ann | nindent 2 }}
  {{- end }}
spec:
  {{- if hasKey $pdbConfig "minAvailable" }}
  minAvailable: {{ $pdbConfig.minAvailable }}
  {{- else }}
  maxUnavailable: {{ coalesce $pdbConfig.maxUnavailable (dig "global" "pdb" "maxUnavailable" nil $values) "25%" }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "common.labels.matchLabels" $labelCtx | nindent 6 }}
    {{- with $pdbConfig.selectorMatchLabels }}
      {{ toYaml . | indent 6 }}
    {{- end }}
  {{- with $pdbConfig.unhealthyPodEvictionPolicy }}
  unhealthyPodEvictionPolicy: {{ . }}
  {{- end }}
{{- end -}}
