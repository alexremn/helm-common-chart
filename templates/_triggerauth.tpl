{{/*
=============================================================================
KEDA TRIGGERAUTHENTICATION TEMPLATE
Renders one KEDA TriggerAuthentication (or ClusterTriggerAuthentication when
.cluster: true) per entry in .Values.triggerAuthentications. Referenced from
existing scaling.triggers[].authenticationRef in chart.scaledobject.

Usage: {{ include "chart.triggerauth" (dict "Values" .Values "Release" .Release "Chart" .Chart "cmp" "web") }}
=============================================================================
*/}}

{{- define "chart.triggerauth" }}
{{- $svc := include "common.appName" . | trim }}
{{- $env := include "common.environment" . | trim }}
{{- $labelCtx := dict "svc" $svc "cmp" "" "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}
{{- $values := include "common._values" . | fromYaml | default dict }}
{{- range $name, $val := dig "triggerAuthentications" dict $values }}
---
apiVersion: keda.sh/v1alpha1
kind: {{ if $val.cluster }}ClusterTriggerAuthentication{{ else }}TriggerAuthentication{{ end }}
metadata:
  name: {{ $name }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
spec:
  {{- with $val.podIdentity }}
  podIdentity: {{ toYaml . | nindent 4 }}
  {{- end }}
  {{- with $val.secretTargetRef }}
  secretTargetRef: {{ toYaml . | nindent 4 }}
  {{- end }}
  {{- with $val.env }}
  env: {{ toYaml . | nindent 4 }}
  {{- end }}
  {{- with $val.hashiCorpVault }}
  hashiCorpVault: {{ toYaml . | nindent 4 }}
  {{- end }}
  {{- with $val.azureKeyVault }}
  azureKeyVault: {{ toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- end }}
