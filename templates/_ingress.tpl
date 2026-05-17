{{/*
=============================================================================
INGRESS TEMPLATES
This file contains templates for Kubernetes Ingress resources.
=============================================================================
*/}}

{{/*
Merge annotations for ingress
Combines global, component-specific, and type-specific annotations
*/}}
{{- define "ingress.annotations" -}}
{{- $baseAnnotations := default dict .baseAnnotations -}}
{{- $ingressAnnotations := dig "annotations" dict .conf -}}
{{- $annotations := mergeOverwrite $baseAnnotations $ingressAnnotations -}}
{{- if $annotations }}
annotations:
  {{- $annotations | toYaml | nindent 2 }}
{{- end }}
{{- end -}}

{{/*
Define a path for ingress
*/}}
{{- define "ingress.path" -}}
{{- $path := default "/" .path -}}
{{- $pathType := default "ImplementationSpecific" .pathType -}}
{{- $svcName := default .defaultSvc .svc | replace "_" "-" -}}
{{- $svcPort := default "http" .port -}}
path: {{ $path }}
pathType: {{ $pathType }}
backend:
  service:
    name: {{ $svcName }}
    port:
      {{- if kindIs "string" $svcPort }}
      name: {{ $svcPort }}
      {{- else }}
      number: {{ $svcPort }}
      {{- end }}
{{- end -}}

{{/*
Define rules for ingress
*/}}
{{- define "ingress.rules" -}}
{{- $conf := .conf }}
{{- $cmp := .cmp }}
rules:
{{- range $conf.domains }}
  - host: {{ if kindIs "map" . }}{{ .host }}{{ else }}{{ . }}{{ end }}
    http:
      paths:
      {{- if kindIs "map" . }}
        {{- range .paths }}
      - {{- include "ingress.path" (dict "path" .path "pathType" .pathType "svc" .svc "defaultSvc" $cmp "port" .port) | nindent 8 }}
        {{- end }}
      {{- else }}
      - {{- include "ingress.path" (dict "defaultSvc" $cmp) | nindent 8 }}
      {{- end }}
{{- end }}
{{- end -}}

{{/*
Generate TLS config for ingress
*/}}
{{- define "ingress.tls" -}}
{{- $conf := .conf }}
{{- $secretName := .secretName }}
{{- $explicitHosts := dig "tls" "hosts" nil $conf }}
tls:
  - hosts:
      {{- if $explicitHosts }}
      {{- range $explicitHosts }}
      - {{ . }}
      {{- end }}
      {{- else }}
      {{- range $conf.domains }}
      - {{ if kindIs "map" . }}{{ .host }}{{ else }}{{ . }}{{ end }}
      {{- end }}
      {{- end }}
    secretName: {{ dig "tls" "secretName" $secretName $conf }}
{{- end -}}

{{/*
Main ingress template
*/}}
{{- define "chart.ingress" -}}
{{- $svc := include "common.appName" . | trim }}
{{- $cmp := include "common.componentName" . | trim }}
{{- $env := include "common.environment" . | trim }}
{{- $componentValues := index .Values (include "common.cmp.valuesKey" .cmp) | default dict }}
{{- $ingressValues := $componentValues.ingress }}
{{- $values := include "common._values" . | fromYaml | default dict }}
{{- $labelCtx := dict "svc" $svc "cmp" $cmp "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}
{{/*
Annotations applied to every ingress for this component:
  - .Values.global.ingress.annotations  (chart-wide defaults)
  - <component>.ingress.annotations     (map-style only; lifted out of the iteration)
Per-entry annotations override these via mergeOverwrite in `ingress.annotations`.
*/}}
{{- $globalIngressAnnotations := dig "global" "ingress" "annotations" dict $values }}

{{- if $ingressValues }}
{{- if kindIs "slice" $ingressValues }}
{{- range $index, $conf := $ingressValues }}
{{- if and (ne (dig "enabled" true $conf) false) $conf.domains }}
{{- $entryName := default (printf "ingress-%d" $index) $conf.name }}
{{- $ingressName := printf "%s-%s" $cmp $entryName | replace "_" "-" }}
{{- $className := coalesce $conf.className (dig "global" "ingress" "className" nil $values) }}

---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ $ingressName }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
  {{- include "ingress.annotations" (dict "baseAnnotations" $globalIngressAnnotations "conf" $conf) | nindent 2 }}
spec:
  {{- if $className }}
  ingressClassName: {{ $className }}
  {{- end }}
  {{- if $conf.tls | default true }}
  {{- include "ingress.tls" (dict "conf" $conf "secretName" $ingressName) | nindent 2 }}
  {{- end }}
  {{- include "ingress.rules" (dict "conf" $conf "cmp" $cmp) | nindent 2 }}
  {{- with $conf.defaultBackend }}
  defaultBackend:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $conf.extraConfig }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- end }}
{{- end }}
{{- else if kindIs "map" $ingressValues }}
{{- $componentBaseAnnotations := dig "annotations" dict $ingressValues }}
{{- $baseAnnotations := mergeOverwrite (deepCopy $globalIngressAnnotations) $componentBaseAnnotations }}
{{- range $type, $conf := $ingressValues }}
{{- if and (ne $type "annotations") (kindIs "map" $conf) (ne (dig "enabled" true $conf) false) $conf.domains }}
{{- $ingressName := printf "%s-%s-ingress" $cmp $type | replace "_" "-" }}
{{- $className := coalesce $conf.className (dig "global" "ingress" "className" nil $values) }}

---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ $ingressName }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
  {{- include "ingress.annotations" (dict "baseAnnotations" $baseAnnotations "conf" $conf) | nindent 2 }}
spec:
  {{- if $className }}
  ingressClassName: {{ $className }}
  {{- end }}
  {{- if $conf.tls | default true }}
  {{- include "ingress.tls" (dict "conf" $conf "secretName" $ingressName) | nindent 2 }}
  {{- end }}
  {{- include "ingress.rules" (dict "conf" $conf "cmp" $cmp) | nindent 2 }}
  {{- with $conf.defaultBackend }}
  defaultBackend:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $conf.extraConfig }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}
{{- end -}}
