{{/*
=============================================================================
CONFIGMAP TEMPLATE
This template renders a Kubernetes ConfigMap with environment-specific configuration.

Usage: {{ include "chart.configmap" (dict "svc" "app-name" "cmp" "component" "Values" .Values) }}
=============================================================================
*/}}

{{- define "config.dict.common" }}{{- end }}
{{- define "config.dict.default" }}{{- end }}
{{- define "config.dict.production" }}{{- end }}
{{- define "config.dict.prod" }}{{- end }}
{{- define "config.dict.staging" }}{{- end }}
{{- define "config.dict.review" }}{{- end }}
{{- define "config.dict.demo" }}{{- end }}
{{- define "config.dict.dev" }}{{- end }}
{{- define "config.dict.sandbox" }}{{- end }}

{{/*
Returns the list of environments where pre-install hook annotations
should be added. Default: empty list (no hook annotation).
Consumers opt in via `global.hooks.preInstallEnvironments: [staging, prod]`.
*/}}
{{- define "config.annotations.default" -}}
{{- $env := .env -}}
{{- $values := include "common._values" . | fromYaml | default dict -}}
{{- $hookEnvs := dig "global" "hooks" "preInstallEnvironments" (list) $values -}}
{{- $hooksEnabled := dig "global" "hooks" "enabled" nil $values -}}
{{- if and (ne $hooksEnabled false) (has $env $hookEnvs) }}
helm.sh/hook: pre-install,pre-upgrade
helm.sh/hook-weight: {{ dig "global" "hooks" "weight" "-5" $values | quote }}
{{- else if hasKey $values "werf" }}
werf.io/weight: {{ dig "werf" "configWeight" "-1" $values | quote }}
{{- end }}
{{- end -}}

{{/*
Render the shared ConfigMap header (separator, apiVersion, kind,
metadata.name, labels, annotations).

Usage:
  {{- include "chart._configmap.header" (dict
        "name" $name
        "labelCtx" $labelCtx
        "env" $env
        "Values" .Values) }}
*/}}
{{- define "chart._configmap.header" -}}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .name }}
  labels:
    {{- include "common.labels" .labelCtx | nindent 4 }}
  {{- $ann := include "config.annotations.default" (dict "env" .env "Values" .Values) | trim }}
  {{- if $ann }}
  annotations:
    {{- $ann | nindent 4 }}
  {{- end }}
{{- end -}}

{{- define "chart.configmap" }}
{{- $svc := include "common.appName" . | trim }}
{{- $cmp := include "common.componentName" . | trim }}
{{- $env := include "common.environment" . | trim }}
{{- $componentValue := index .Values (include "common.cmp.valuesKey" .cmp) | default dict }}
{{- $labelCtx := dict "svc" $svc "cmp" $cmp "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}

{{- if hasKey .Values "configs" }}
{{- range $name, $val := .Values.configs }}
{{ include "chart._configmap.header" (dict "name" $name "labelCtx" $labelCtx "env" $env "Values" $.Values) }}
{{- if $val.immutable }}
immutable: true
{{- end }}
data:
{{- /* F2: scope tpl context to Values/Release/Chart + this configmap's
       componentValues instead of leaking the full chart root via `$`. */ -}}
{{- $tplCtx := dict "Values" $.Values "Release" $.Release "Chart" $.Chart "componentValues" $val }}
{{- range $key, $value := $val.data }}
  {{ $key }}: {{ tpl (toString $value) $tplCtx | quote }}
{{- end }}
{{- range $glob := $val.fromFiles | default list }}
{{- range $path, $content := $.Files.Glob $glob }}
  {{ base $path }}: |
    {{- $content | toString | nindent 4 }}
{{- end }}
{{- end }}
{{- if $val.binaryFromFiles }}
binaryData:
{{- range $glob := $val.binaryFromFiles }}
{{- range $path, $content := $.Files.Glob $glob }}
  {{ base $path }}: {{ $content | b64enc | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- else }}
{{- include "chart._configmap.header" (dict "name" $cmp "labelCtx" $labelCtx "env" $env "Values" .Values) }}
data:
{{- $commonConfig := include "config.dict.common" . | default "" | trim }}
{{- if ne $commonConfig "" }}
  {{ $commonConfig | nindent 2 }}
{{- end }}
{{- $envSpecificTemplate := printf "config.dict.%s" $env }}
{{- $envConfig := include $envSpecificTemplate . | default "" | trim }}
{{- if ne $envConfig "" }}
  {{ $envConfig | nindent 2 }}
{{- end }}
{{- if and (hasKey $componentValue "configmap") (hasKey $componentValue.configmap "data") }}
  {{- /* F2: scope tpl context to Values/Release/Chart + componentValues
         instead of leaking the full chart root via `$`. */ -}}
  {{- $tplCtx := dict "Values" $.Values "Release" $.Release "Chart" $.Chart "componentValues" $componentValue }}
  {{- range $key, $value := $componentValue.configmap.data }}
  {{ $key }}: {{ tpl (toString $value) $tplCtx | quote }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create a ConfigMap specifically for binary data
Usage: {{ include "chart.binaryConfigmap" (dict "svc" "app-name" "cmp" "component" "Values" .Values) }}
*/}}
{{/*
Lowercase canonical alias (matches chart.configmap casing).
`chart.binaryConfigmap` (camelCase) is retained as a deprecated alias for one minor.
*/}}
{{- define "chart.binaryconfigmap" -}}
{{- include "chart.binaryConfigmap" . -}}
{{- end -}}

{{- define "chart.binaryConfigmap" }}
{{- $svc := include "common.appName" . | trim }}
{{- $cmp := include "common.componentName" . | trim }}
{{- $env := include "common.environment" . | trim }}
{{- $componentValue := index .Values (include "common.cmp.valuesKey" .cmp) | default dict }}
{{- /* label/render context; canonical shape: common.workload.context.doc */ -}}
{{- $labelCtx := dict "svc" $svc "cmp" $cmp "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}
{{- if and (hasKey $componentValue "configmap") (hasKey $componentValue.configmap "binaryData") }}
{{- include "chart._configmap.header" (dict "name" (printf "%s-files" $cmp) "labelCtx" $labelCtx "env" $env "Values" .Values) }}
binaryData:
  {{- range $key, $value := $componentValue.configmap.binaryData }}
  {{ $key }}: {{ $value | quote }}
  {{- end }}
{{- end }}
{{- end -}}
