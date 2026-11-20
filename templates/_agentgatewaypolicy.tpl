{{/*
=============================================================================
AGENTGATEWAYPOLICY TEMPLATE (agentgateway)
Renders one agentgateway.dev/v1alpha1 AgentgatewayPolicy per entry of
`<component>.agentgatewayPolicies`: what a route on agentgateway takes from a
policy rather than from the HTTPRoute itself (CORS, basic auth, a direct
response, ...).

An entry is the policy spec as is, plus optional `annotations`. Without
`targetRefs` or `targetSelectors` it targets every HTTPRoute chart.httproute
renders for the component.

Usage: {{ include "chart.agentgatewaypolicy" (dict "Values" .Values "Release" .Release "Chart" .Chart "cmp" "web") }}
=============================================================================
*/}}

{{- define "chart.agentgatewaypolicy" -}}
{{- $svc := include "common.appName" . | trim }}
{{- $cmp := include "common.componentName" . | trim }}
{{- $env := include "common.environment" . | trim }}
{{- $componentValues := index .Values (include "common.cmp.valuesKey" .cmp) | default dict }}
{{- $labelCtx := dict "svc" $svc "cmp" $cmp "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}
{{- /* The component's HTTPRoutes, by the names chart.httproute gives them: <cmp>, and common.httproute.entryName. */ -}}
{{- $routes := list }}
{{- if $componentValues.httpRoute }}
{{- $routes = append $routes $cmp }}
{{- end }}
{{- if kindIs "map" $componentValues.httpRoutes }}
{{- range $name, $hr := $componentValues.httpRoutes }}
{{- if $hr }}
{{- $routes = append $routes (include "common.httproute.entryName" (dict "cmp" $cmp "key" $name) | trim) }}
{{- end }}
{{- end }}
{{- end }}
{{- $policies := $componentValues.agentgatewayPolicies }}
{{- if kindIs "map" $policies }}
{{- range $name, $policy := $policies }}
{{- if $policy }}
{{- $targeted := or $policy.targetRefs $policy.targetSelectors }}
{{- if not (or $targeted $routes) }}
{{- fail (printf "%s.agentgatewayPolicies.%s: set targetRefs or targetSelectors (the component has no httpRoute to default to)" $cmp $name) }}
{{- end }}
---
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata:
  name: {{ include "common.cmp.dns" (printf "%s-%s" $cmp $name) | trim }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
  {{- with $policy.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  {{- $spec := omit $policy "annotations" }}
  {{- if not $targeted }}
  {{- /* Also drops an explicitly empty targetRefs/targetSelectors: the default below replaces it. */ -}}
  {{- $spec = omit $spec "targetRefs" "targetSelectors" }}
  targetRefs:
    {{- range $routes }}
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: {{ . }}
    {{- end }}
  {{- end }}
  {{- with $spec }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}
