{{/*
=============================================================================
RBAC TEMPLATE
Per-component (auto-binds to the component's ServiceAccount) and top-level
(.Values.rbac map; freeform).

Per-component shapes:
  <component>.rbac.role.rules                 → Role + RoleBinding (in release ns)
  <component>.rbacCluster.clusterRole.rules   → ClusterRole + ClusterRoleBinding

Top-level shape:
  rbac:
    <name>:
      kind: Role | ClusterRole
      rules: [...]
      subjects: [...]      # optional; if omitted, no binding emitted
      namespace: <ns>      # optional; only for kind: Role
=============================================================================
*/}}

{{/*
Render a Role/ClusterRole and its companion *Binding.

Parameters:
  kind        — "Role" or "ClusterRole"
  name        — metadata.name for both objects
  bindingName — metadata.name for the binding (defaults to .name)
  namespace   — optional, only emitted for kind=Role
  labelCtx    — labelCtx dict
  rules       — list of rule objects
  subjects    — list of binding subjects (skip binding when empty)
*/}}
{{- define "chart._rbac.pair" }}
{{- $kind := required "chart._rbac.pair: kind required" .kind -}}
{{- $name := required "chart._rbac.pair: name required" .name -}}
{{- $bindingName := default $name .bindingName -}}
{{- $bindingKind := printf "%sBinding" $kind -}}
{{- $emitNamespace := and (eq $kind "Role") .namespace }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: {{ $kind }}
metadata:
  name: {{ $name }}
  labels:
    {{- include "common.labels" .labelCtx | nindent 4 }}
  {{- if $emitNamespace }}
  namespace: {{ .namespace }}
  {{- end }}
rules: {{ toYaml .rules | nindent 2 }}
{{- if .subjects }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: {{ $bindingKind }}
metadata:
  name: {{ $bindingName }}
  labels:
    {{- include "common.labels" .labelCtx | nindent 4 }}
  {{- if $emitNamespace }}
  namespace: {{ .namespace }}
  {{- end }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: {{ $kind }}
  name: {{ $name }}
subjects:
  {{- range $s := .subjects }}
  - {{ toYaml $s | nindent 4 | trim }}
  {{- end }}
{{- end }}
{{- end }}

{{- define "chart.rbac" }}
{{- $svc := include "common.appName" . | trim }}
{{- $cmp := include "common.componentName" . | trim }}
{{- $env := include "common.environment" . | trim }}
{{- $componentValues := index .Values (include "common.cmp.valuesKey" .cmp) | default dict }}
{{- $labelCtx := dict "svc" $svc "cmp" $cmp "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}
{{- $saName := include "common.serviceAccountName" (dict "component" $componentValues "fallback" $cmp) }}
{{- $saSubject := list (dict "kind" "ServiceAccount" "name" $saName "namespace" $.Release.Namespace) }}

{{- /* Per-component namespaced Role + RoleBinding. */ -}}
{{- with $componentValues.rbac }}
{{- with .role }}
{{- include "chart._rbac.pair" (dict
    "kind" "Role"
    "name" $cmp
    "labelCtx" $labelCtx
    "rules" .rules
    "subjects" $saSubject) }}
{{- end }}
{{- end }}

{{- /* Per-component cluster-scoped ClusterRole + ClusterRoleBinding. */ -}}
{{- with $componentValues.rbacCluster }}
{{- with .clusterRole }}
{{- include "chart._rbac.pair" (dict
    "kind" "ClusterRole"
    "name" (printf "%s-%s" $svc $cmp)
    "labelCtx" $labelCtx
    "rules" .rules
    "subjects" $saSubject) }}
{{- end }}
{{- end }}

{{- /* Top-level rbac map (freeform). */ -}}
{{- $values := include "common._values" . | fromYaml | default dict -}}
{{- range $name, $val := dig "rbac" dict $values }}
{{- include "chart._rbac.pair" (dict
    "kind" (default "Role" $val.kind)
    "name" $name
    "namespace" (default "" $val.namespace)
    "labelCtx" $labelCtx
    "rules" $val.rules
    "subjects" $val.subjects) }}
{{- end }}
{{- end }}
