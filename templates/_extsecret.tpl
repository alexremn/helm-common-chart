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

{{/*
Returns the list of environments where pre-install hook annotations
should be added. Default: empty list (no hook annotation).
Consumers opt in via `global.hooks.preInstallEnvironments: [staging, prod]`.
*/}}
{{- define "secrets.annotations.default" }}
{{- $env := .env }}
{{- $values := include "common._values" . | fromYaml | default dict }}
{{- /* `force-sync` drives ESO to re-reconcile when its value changes.
       Default: per-render `now` timestamp so ESO always reconciles on upgrade.
       Opt out with `global.externalSecrets.forceSync: false`, which falls
       back to a stable per-revision value (noise-free diffs, no churn). */ -}}
{{- $forceSync := dig "global" "externalSecrets" "forceSync" true $values }}
{{- if $forceSync }}
force-sync: {{ now | quote }}
{{- else }}
{{- $rev := "1" }}
{{- if .Release }}{{- $rev = .Release.Revision | toString }}{{- end }}
force-sync: {{ $rev | quote }}
{{- end }}
{{- $hookEnvs := dig "global" "hooks" "preInstallEnvironments" (list) $values }}
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
{{- $values := include "common._values" . | fromYaml | default dict }}
{{- $globalStore := dig "global" "secretStore" "" $values }}
{{- /* ExternalSecret apiVersion. `external-secrets.io/v1` is the default (ESO
       >= 0.14.0). Clusters running ESO 0.9.x-0.13.x only serve `v1beta1`;
       set `global.externalSecrets.apiVersion: external-secrets.io/v1beta1`
       there. Validated so a typo fails loudly instead of at admission. */ -}}
{{- $esoApiVersion := dig "global" "externalSecrets" "apiVersion" "external-secrets.io/v1" $values }}
{{- if not (has $esoApiVersion (list "external-secrets.io/v1" "external-secrets.io/v1beta1")) }}
{{- fail (printf "invalid global.externalSecrets.apiVersion %q; must be external-secrets.io/v1 or external-secrets.io/v1beta1" $esoApiVersion) }}
{{- end }}
{{- $labelCtx := dict "svc" $svc "cmp" $cmp "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}

{{- if $secrets }}
{{- range $name, $val := $secrets }}
---
apiVersion: {{ $esoApiVersion }}
kind: ExternalSecret
metadata:
  name: {{ $name }}
  labels: {{ include "common.labels" $labelCtx | nindent 4 }}
  {{- $ann := include "secrets.annotations.default" (dict "env" $env "Values" $.Values "Release" $.Release) | trim }}
  {{- if $ann }}
  annotations: {{ $ann | nindent 4 }}
  {{- end }}
spec:
  refreshInterval: {{ dig "refreshInterval" "10000h" $val | quote }}
  secretStoreRef:
    name: {{ required (printf "secrets.%s.secretStore (or global.secretStore) is required for ExternalSecret" $name) (coalesce (dig "secretStore" "" $val) $globalStore) }}
    {{- $kind := dig "secretStoreKind" "ClusterSecretStore" $val }}
    {{- if not (has $kind (list "ClusterSecretStore" "SecretStore")) }}
    {{ fail (printf "invalid secretStoreKind %q for component %s (secret %s); must be ClusterSecretStore or SecretStore" $kind $cmp $name) }}
    {{- end }}
    kind: {{ $kind }}
  target:
    name: {{ default $name $val.secretName }}
    creationPolicy: {{ default "Owner" $val.creationPolicy }}
    {{- with $val.deletionPolicy }}
    deletionPolicy: {{ . }}
    {{- end }}
    {{- with $val.template }}
    template: {{ toYaml . | nindent 6 }}
    {{- end }}
  {{- with (include "secrets.external.generated" $val | trim) }}
  {{- . | nindent 2 }}
  {{- end }}
  {{- with $val.dataFrom }}
  dataFrom: {{ toYaml . | nindent 4 }}
  {{- end }}
  data:
    {{- include "secrets.generate" (dict "key" $val.secretKey "values" $val.properties) | trimPrefix "\n" | nindent 4}}
    {{- range $inc := $val.includes }}
    {{- $envSecretsTemplate := printf "secrets.dict.%s" $inc }}
    {{- $envSecrets := include $envSecretsTemplate $ | default "" | trim }}
    {{- if ne $envSecrets "" }}
    {{- if contains "key:" $envSecrets }}
    {{- $secretData := fromYaml $envSecrets }}
    {{- if and $secretData (hasKey $secretData "key") (hasKey $secretData "values") }}
    {{- include "secrets.generate" $secretData | trimPrefix "\n" | nindent 4}}
    {{- end }}
    {{- end }}
    {{- end }}
    {{- end }}
{{- end }}
{{- end }}
{{- end }}
