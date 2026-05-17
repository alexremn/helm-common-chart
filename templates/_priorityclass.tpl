{{/*
=============================================================================
PRIORITYCLASS TEMPLATE
Renders one cluster-scoped PriorityClass per entry in .Values.priorityClasses.

Usage: {{ include "chart.priorityclass" (dict "Values" .Values "Release" .Release "Chart" .Chart "cmp" "web") }}
=============================================================================
*/}}

{{- define "chart.priorityclass" }}
{{- $svc := include "common.appName" . | trim }}
{{- $env := include "common.environment" . | trim }}
{{- $labelCtx := dict "svc" $svc "cmp" "" "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}
{{- $values := include "common._values" . | fromYaml | default dict }}
{{- range $name, $val := dig "priorityClasses" dict $values }}
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: {{ $name }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
value: {{ required (printf "priorityClasses entry %q must set value" $name) $val.value }}
globalDefault: {{ default false $val.globalDefault }}
{{- with $val.description }}
description: {{ . | quote }}
{{- end }}
{{- with $val.preemptionPolicy }}
preemptionPolicy: {{ . }}
{{- end }}
{{- end }}
{{- end }}
