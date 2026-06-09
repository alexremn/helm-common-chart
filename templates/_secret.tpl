{{/*
=============================================================================
NATIVE SECRET TEMPLATE
Renders one Secret per entry in .Values.nativeSecrets. Honors hooks/weights
the same way as configs and ExternalSecrets.

Use chart.extsecret for ExternalSecrets (managed by external-secrets.io); use
chart.secret for native K8s Secrets (dockerconfigjson, TLS certs, short-lived
bootstrap data).

Usage: {{ include "chart.secret" (dict "Values" .Values "Release" .Release "Chart" .Chart "cmp" "web") }}
=============================================================================
*/}}

{{- define "chart.secret" }}
{{- $svc := include "common.appName" . | trim }}
{{- $cmp := include "common.componentName" . | trim }}
{{- $env := include "common.environment" . | trim }}
{{- $labelCtx := dict "svc" $svc "cmp" $cmp "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}

{{- if hasKey .Values "nativeSecrets" }}
{{- range $name, $val := .Values.nativeSecrets }}
---
apiVersion: v1
kind: Secret
metadata:
  name: {{ $name }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
  {{- $ann := include "config.annotations.default" (dict "env" $env "Values" $.Values) | trim }}
  {{- if $ann }}
  annotations:
    {{- $ann | nindent 4 }}
  {{- end }}
type: {{ default "Opaque" $val.type }}
{{- if $val.immutable }}
immutable: true
{{- end }}
{{- with $val.data }}
data: {{ toYaml . | nindent 2 }}
{{- end }}
{{- with $val.stringData }}
stringData:
{{- /* F2: scope tpl context to Values/Release/Chart + this secret's
       componentValues ($val) instead of leaking the full chart root via `$`. */ -}}
{{- /* P3-3: stringData runs through `tpl` by default. Opt out chart-wide via
       `global.tpl.envValues: false` or per-secret via `envRaw: true`. */ -}}
{{- $tplCtx := dict "Values" $.Values "Release" $.Release "Chart" $.Chart "componentValues" $val }}
{{- $tplEnabled := dig "global" "tpl" "envValues" true (toYaml $.Values | fromYaml) }}
{{- if (dig "envRaw" false $val) }}{{- $tplEnabled = false }}{{- end }}
{{- range $k, $v := . }}
  {{ $k }}: {{ if $tplEnabled }}{{ tpl (toString $v) $tplCtx | quote }}{{ else }}{{ toString $v | quote }}{{ end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
