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
{{- /* `tls` may be a bool (e.g. `tls: true`) or a map; only dig into it when
       it's a map so booleans don't blow up `dig`. */ -}}
{{- $tlsMap := dict }}
{{- if kindIs "map" $conf.tls }}{{ $tlsMap = $conf.tls }}{{- end }}
{{- $explicitHosts := dig "hosts" nil $tlsMap }}
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
    secretName: {{ dig "secretName" $secretName $tlsMap }}
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

{{- if $ingressValues -}}
{{- /* Normalize slice + map inputs to a uniform list of entries so a single
       rendering loop covers both shapes. Each entry carries:
         name             — final Ingress object name
         conf             — the per-entry config map
         baseAnnotations  — the annotations layered under per-entry overrides
*/ -}}
{{- $entries := list -}}
{{- if kindIs "slice" $ingressValues -}}
  {{- range $index, $conf := $ingressValues -}}
    {{- if and (ne (dig "enabled" true $conf) false) $conf.domains -}}
      {{- $entryName := default (printf "ingress-%d" $index) $conf.name -}}
      {{- $name := printf "%s-%s" $cmp $entryName | replace "_" "-" -}}
      {{- $entries = append $entries (dict "name" $name "conf" $conf "baseAnnotations" $globalIngressAnnotations) -}}
    {{- end -}}
  {{- end -}}
{{- else if kindIs "map" $ingressValues -}}
  {{- $componentBaseAnnotations := dig "annotations" dict $ingressValues -}}
  {{- $mapBaseAnnotations := mergeOverwrite (deepCopy $globalIngressAnnotations) $componentBaseAnnotations -}}
  {{- range $type, $conf := $ingressValues -}}
    {{- if and (ne $type "annotations") (kindIs "map" $conf) (ne (dig "enabled" true $conf) false) $conf.domains -}}
      {{- $name := printf "%s-%s-ingress" $cmp $type | replace "_" "-" -}}
      {{- $entries = append $entries (dict "name" $name "conf" $conf "baseAnnotations" $mapBaseAnnotations) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{- range $entry := $entries }}
{{- $conf := $entry.conf }}
{{- $ingressName := $entry.name }}
{{- $className := coalesce $conf.className (dig "global" "ingress" "className" nil $values) }}

---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ $ingressName }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
  {{- include "ingress.annotations" (dict "baseAnnotations" $entry.baseAnnotations "conf" $conf) | nindent 2 }}
spec:
  {{- if $className }}
  ingressClassName: {{ $className }}
  {{- end }}
  {{- /* F6: Only emit `tls:` when the consumer opts in. A consumer omitting
         `tls:` (or setting it to `false`) gets a plain HTTP Ingress instead of
         a malformed block that references a non-existent Secret. An empty map
         (`tls: {}`) or `tls: true` is still truthy, preserving the auto-host
         + auto-secretName behaviour for consumers that explicitly request it. */ -}}
  {{- if $conf.tls }}
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
{{- end -}}
{{- end -}}
{{- end -}}
