{{/*
=============================================================================
EXTERNAL SECRET TEMPLATE
This template renders an ExternalSecret for the external-secrets.io operator.

Usage: {{ include "chart.extsecret" (dict "svc" "app-name" "cmp" "component" "Values" .Values) }}
=============================================================================
*/}}

{{- define "secrets.dict.generated" }}{{- end }}
{{- define "secrets.dict.common" }}{{- end }}
{{- define "secrets.dict.default" }}{{- end }}
{{- define "secrets.dict.production" }}{{- end }}
{{- define "secrets.dict.staging" }}{{- end }}
{{- define "secrets.dict.review" }}{{- end }}
{{- define "secrets.dict.demo" }}{{- end }}
{{- define "secrets.dict.dev" }}{{- end }}
{{- define "secrets.dict.sandbox" }}{{- end }}

{{- define "secrets.annotations.default" }}
{{- $env := .env }}
{{- $values := include "common._values" . | fromYaml | default dict }}
force-sync: {{ now | quote }}
{{- $hookEnvs := dig "global" "hooks" "preInstallEnvironments" (list "review") $values }}
{{- $hooksEnabled := dig "global" "hooks" "enabled" nil $values }}
{{- if and (ne $hooksEnabled false) (has $env $hookEnvs) }}
helm.sh/hook: pre-install,pre-upgrade
helm.sh/hook-weight: {{ dig "global" "hooks" "weight" "-5" $values | quote }}
{{- else if hasKey $values "werf" }}
werf.io/weight: {{ dig "werf" "secretWeight" "-1" $values | quote }}
{{- end }}
{{- end }}

{{/* Generate template for review environments or when explicitly specified */}}
{{- define "secrets.external.generated" }}
{{- $val := dig "generated" "" . }}
{{- if $val }}
template:
  mergePolicy: {{ dig "mergePolicy" "Merge" $val }}
  engineVersion: v2
  data:
  {{ $val.data | nindent 4 }}
  {{ range $inc := $val.includes }}
  {{- $envSecretsTemplate := printf "secrets.dict.%s" $inc }}
  {{ include $envSecretsTemplate $ | nindent 4 }}
  {{- end }}
  {{- with $val.templateData }}
    {{ toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- end }}

{{- define "chart.extsecret" }}
{{- $svc := include "common.appName" . | trim }}
{{- $cmp := include "common.componentName" . | trim }}
{{- $env := include "common.environment" . | trim }}
{{- $secrets := .Values.secrets }}
{{- $labelCtx := dict "svc" $svc "cmp" $cmp "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}

{{- if $secrets }}
{{- range $name, $val := $secrets }}
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: {{ $name }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
  annotations: {{ include "secrets.annotations.default" (dict "env" $env "Values" $.Values) | nindent 4 }}
spec:
  refreshInterval: {{ dig "refreshInterval" "10000h" $val | quote }}
  secretStoreRef:
    name: {{ dig "secretStore" "secrets-manager" $val }}
    kind: {{ dig "secretStoreKind" "ClusterSecretStore" $val }}
  target:
    name: {{ default $name $val.secretName }}
    creationPolicy: {{ default "Owner" $val.creationPolicy }}
    {{- with $val.deletionPolicy }}
    deletionPolicy: {{ . }}
    {{- end }}
    {{- with $val.template }}
    template: {{ toYaml . | nindent 6 }}
    {{- end }}
{{ include "secrets.external.generated" $val | nindent 2 }}
  {{- with $val.dataFrom }}
  dataFrom: {{ toYaml . | nindent 4 }}
  {{- end }}
  data:
{{/* Generate secrets from the provided key and values */}}
{{ include "secrets.generate" (dict "key" $val.secretKey "values" $val.properties) | nindent 4 }}
{{/* Include environment-specific secrets - safely catch template not found errors */}}
{{ range $inc := $val.includes }}
{{- $envSecretsTemplate := printf "secrets.dict.%s" $inc }}
{{/* Wrap template include in an if/else block to capture error and provide empty default */}}
{{- $envSecrets := include $envSecretsTemplate $ | default "" | trim }}
{{- if ne $envSecrets "" }}
  {{- if contains "key:" $envSecrets }}
    {{- $secretData := fromYaml $envSecrets }}
    {{- if and $secretData (hasKey $secretData "key") (hasKey $secretData "values") }}
      {{ include "secrets.generate" $secretData | indent 4 }}
    {{- end }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
