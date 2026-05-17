{{/*
=============================================================================
PERSISTENT VOLUME CLAIM TEMPLATE
This template renders Kubernetes PersistentVolumeClaims for components.
=============================================================================
*/}}

{{- define "chart.pvc" }}
{{- $svc := include "common.appName" . | trim }}
{{- $cmp := include "common.componentName" . | trim }}
{{- $env := include "common.environment" . | trim }}
{{- $componentValues := index .Values (include "common.cmp.valuesKey" .cmp) | default dict }}
{{- $labelCtx := dict "svc" $svc "cmp" $cmp "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}

{{- if not (hasKey $componentValues "persistence") }}
  {{- if .Debug }}
    {{ fail (printf "Component %s does not have persistence configuration" $cmp) }}
  {{- else }}
    {{ print (printf "Skipping PVC for component '%s': no persistence defined" $cmp) | quote | printf "# %s" }}
  {{- end }}
{{- else }}
  {{- $persistence := $componentValues.persistence }}
  {{- if kindIs "map" $persistence }}
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: {{ default $cmp $persistence.name }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
  {{- $ann := include "common.annotations" $persistence | trim }}
  {{- if $ann }}
  annotations:
    {{- $ann | nindent 2 }}
  {{- end }}
spec:
  {{- include "common.pvc.spec" $persistence | nindent 2 }}

  {{- else if kindIs "slice" $persistence }}
    {{- range $pvc := $persistence }}
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: {{ required "PVC name is required" $pvc.name }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
  {{- $ann := include "common.annotations" $pvc | trim }}
  {{- if $ann }}
  annotations:
    {{- $ann | nindent 2 }}
  {{- end }}
spec:
  {{- include "common.pvc.spec" $pvc | nindent 2 }}
    {{- end }}
  {{- end }}
{{- end }}
{{- end }}
