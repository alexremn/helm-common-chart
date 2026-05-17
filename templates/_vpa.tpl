{{/*
=============================================================================
VERTICAL POD AUTOSCALER TEMPLATE
Renders a VPA targeting the component's Deployment by default. The VPA
operator must be installed in the cluster.
=============================================================================
*/}}

{{- define "chart.vpa" }}
{{- $svc := include "common.appName" . | trim }}
{{- $cmp := include "common.componentName" . | trim }}
{{- $env := include "common.environment" . | trim }}
{{- $componentValues := index .Values (include "common.cmp.valuesKey" .cmp) | default dict }}
{{- $vpa := $componentValues.vpa | default dict }}
{{- $labelCtx := dict "svc" $svc "cmp" $cmp "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}
{{- if $vpa }}
---
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: {{ $cmp }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
  {{- with $vpa.annotations }}
  annotations: {{ toYaml . | nindent 4 }}
  {{- end }}
spec:
  targetRef:
    apiVersion: {{ default "apps/v1" (dig "targetRef" "apiVersion" "apps/v1" $vpa) }}
    kind: {{ default "Deployment" (dig "targetRef" "kind" "Deployment" $vpa) }}
    name: {{ default $cmp (dig "targetRef" "name" $cmp $vpa) }}
  {{- with $vpa.updatePolicy }}
  updatePolicy: {{ toYaml . | nindent 4 }}
  {{- end }}
  {{- with $vpa.resourcePolicy }}
  resourcePolicy: {{ toYaml . | nindent 4 }}
  {{- end }}
  {{- with $vpa.recommenders }}
  recommenders: {{ toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- end }}
