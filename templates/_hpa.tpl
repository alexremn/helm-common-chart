{{/*
=============================================================================
HORIZONTAL POD AUTOSCALER TEMPLATE
Renders an HPA whose scaleTargetRef.kind defaults to Deployment. For
StatefulSet (or any non-Deployment) workloads the consumer MUST set
<component>.hpa.kind (and .hpa.apiVersion if it differs from apps/v1);
the library cannot infer the workload kind. Mutually exclusive with KEDA's
<component>.scaling — chart.hpa fails fast if both are set on the same component.
=============================================================================
*/}}

{{- define "chart.hpa" }}
{{- $svc := include "common.appName" . | trim }}
{{- $cmp := include "common.componentName" . | trim }}
{{- $env := include "common.environment" . | trim }}
{{- $componentValues := index .Values (include "common.cmp.valuesKey" .cmp) | default dict }}
{{- $hpa := $componentValues.hpa | default dict }}
{{- $labelCtx := dict "svc" $svc "cmp" $cmp "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}
{{- if $hpa }}
{{- if $componentValues.scaling }}
{{- fail (printf "Component '%s' has both .hpa and .scaling set. Pick one — chart.hpa (native HPA) or chart.scaledobject (KEDA)." $cmp) }}
{{- end }}
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ $cmp }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
  {{- with $hpa.annotations }}
  annotations: {{ toYaml . | nindent 4 }}
  {{- end }}
spec:
  {{- $hpaKind := default "Deployment" $hpa.kind }}
  {{- if not (has $hpaKind (list "Deployment" "StatefulSet" "ReplicaSet")) }}
  {{- fail (printf "chart.hpa: component '%s' .hpa.kind must be one of Deployment|StatefulSet|ReplicaSet, got %q" $cmp $hpaKind) }}
  {{- end }}
  scaleTargetRef:
    apiVersion: {{ default "apps/v1" $hpa.apiVersion }}
    kind: {{ $hpaKind }}
    name: {{ default $cmp $hpa.targetName }}
  minReplicas: {{ default 1 $hpa.minReplicas }}
  maxReplicas: {{ required "hpa.maxReplicas is required" $hpa.maxReplicas }}
  {{- with $hpa.metrics }}
  metrics: {{ toYaml . | nindent 4 }}
  {{- end }}
  {{- with $hpa.behavior }}
  behavior: {{ toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- end }}
