{{/*
=============================================================================
NETWORKPOLICY TEMPLATE
Per-component (selects the component's pods automatically) and top-level
(.Values.networkPolicies map; freeform passthrough).
=============================================================================

DEFAULT: policyTypes = [Ingress] only. Egress is unrestricted by default
(matches Kubernetes default behavior when an Egress rule is absent).
Consumers wanting egress restriction MUST set:
  <cmp>.networkPolicy.policyTypes: [Ingress, Egress]
and supply <cmp>.networkPolicy.egress rules. An empty egress: [] under
Egress policyType means deny-all egress.

See tests/smoke/values-networkpolicy-egress.yaml for an example.
*/}}

{{/*
Resolve a NetworkPolicy port. If the value is a string, treat it as a port
*name* and resolve against the component's .ports map (NetworkPolicy ports
must reference container port numbers, not service port names). If numeric,
pass through.
*/}}
{{- define "networkPolicy.port" -}}
{{- $port := .port -}}
{{- $componentValues := .componentValues -}}
{{- if kindIs "string" $port -}}
{{- $resolved := dig "ports" $port nil $componentValues -}}
{{- if not $resolved -}}
  {{- fail (printf "NetworkPolicy port name %q not found in component.ports" $port) -}}
{{- end -}}
{{- if kindIs "map" $resolved -}}
{{ $resolved.containerPort }}
{{- else -}}
{{ $resolved }}
{{- end -}}
{{- else -}}
{{ $port }}
{{- end -}}
{{- end -}}

{{- define "chart.networkpolicy" }}
{{- $svc := include "common.appName" . | trim }}
{{- $cmp := include "common.componentName" . | trim }}
{{- $env := include "common.environment" . | trim }}
{{- $componentValues := index .Values (include "common.cmp.valuesKey" .cmp) | default dict }}
{{- $np := $componentValues.networkPolicy | default dict }}
{{- $labelCtx := dict "svc" $svc "cmp" $cmp "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}

{{- /* Per-component NetworkPolicy. */ -}}
{{- if and $np (ne (dig "enabled" true $np) false) }}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ $cmp }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
  {{- with $np.annotations }}
  annotations: {{ toYaml . | nindent 4 }}
  {{- end }}
spec:
  podSelector:
    matchLabels:
      {{- include "common.labels.matchLabels" $labelCtx | nindent 6 }}
  policyTypes: {{ default (list "Ingress") $np.policyTypes | toYaml | nindent 4 }}
  {{- with $np.ingress }}
  ingress:
  {{- range $rule := . }}
    - {{- if $rule.from }}
      from: {{ toYaml $rule.from | nindent 8 }}
      {{- end }}
      {{- if $rule.ports }}
      ports:
      {{- range $port := $rule.ports }}
        - protocol: {{ default "TCP" $port.protocol }}
          port: {{ include "networkPolicy.port" (dict "port" $port.port "componentValues" $componentValues) }}
          {{- with $port.endPort }}
          endPort: {{ . }}
          {{- end }}
      {{- end }}
      {{- end }}
  {{- end }}
  {{- end }}
  {{- with $np.egress }}
  egress:
  {{- range $rule := . }}
    - {{- if $rule.to }}
      to: {{ toYaml $rule.to | nindent 8 }}
      {{- end }}
      {{- if $rule.ports }}
      ports:
      {{- range $port := $rule.ports }}
        - protocol: {{ default "TCP" $port.protocol }}
          port: {{ include "networkPolicy.port" (dict "port" $port.port "componentValues" $componentValues) }}
          {{- with $port.endPort }}
          endPort: {{ . }}
          {{- end }}
      {{- end }}
      {{- end }}
  {{- end }}
  {{- end }}
{{- end }}

{{- /* Top-level networkPolicies map: freeform spec passthrough. Object name is
       the verbatim consumer key; build a component-free label ctx so these
       shared resources are not stamped with a component they don't own. */ -}}
{{- $values := include "common._values" . | fromYaml | default dict -}}
{{- $topLabelCtx := dict "svc" $svc "cmp" "" "env" $env "Values" .Values "Release" .Release "Chart" .Chart -}}
{{- range $name, $spec := dig "networkPolicies" dict $values }}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ $name }}
  labels:
    {{- include "common.labels" $topLabelCtx | nindent 4 }}
spec: {{ toYaml $spec | nindent 2 }}
{{- end }}
{{- end }}
