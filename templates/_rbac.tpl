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

{{- define "chart.rbac" }}
{{- $svc := include "common.appName" . | trim }}
{{- $cmp := include "common.componentName" . | trim }}
{{- $env := include "common.environment" . | trim }}
{{- $componentValues := index .Values (include "common.cmp.valuesKey" .cmp) | default dict }}
{{- $labelCtx := dict "svc" $svc "cmp" $cmp "env" $env "Values" .Values "Release" .Release "Chart" .Chart }}
{{- $saName := dig "serviceAccount" "name" $cmp $componentValues }}

{{- /* Per-component namespaced Role + RoleBinding. */ -}}
{{- with $componentValues.rbac }}
{{- with .role }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: {{ $cmp }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
rules: {{ toYaml .rules | nindent 2 }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ $cmp }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: {{ $cmp }}
subjects:
  - kind: ServiceAccount
    name: {{ $saName }}
    namespace: {{ $.Release.Namespace }}
{{- end }}
{{- end }}

{{- /* Per-component cluster-scoped ClusterRole + ClusterRoleBinding. */ -}}
{{- with $componentValues.rbacCluster }}
{{- with .clusterRole }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: {{ $svc }}-{{ $cmp }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
rules: {{ toYaml .rules | nindent 2 }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: {{ $svc }}-{{ $cmp }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: {{ $svc }}-{{ $cmp }}
subjects:
  - kind: ServiceAccount
    name: {{ $saName }}
    namespace: {{ $.Release.Namespace }}
{{- end }}
{{- end }}

{{- /* Top-level rbac map (freeform). */ -}}
{{- $values := include "common._values" . | fromYaml | default dict -}}
{{- range $name, $val := dig "rbac" dict $values }}
{{- $kind := default "Role" $val.kind }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: {{ $kind }}
metadata:
  name: {{ $name }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
  {{- if and (eq $kind "Role") $val.namespace }}
  namespace: {{ $val.namespace }}
  {{- end }}
rules: {{ toYaml $val.rules | nindent 2 }}
{{- if $val.subjects }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: {{ if eq $kind "Role" }}RoleBinding{{ else }}ClusterRoleBinding{{ end }}
metadata:
  name: {{ $name }}
  labels:
    {{- include "common.labels" $labelCtx | nindent 4 }}
  {{- if and (eq $kind "Role") $val.namespace }}
  namespace: {{ $val.namespace }}
  {{- end }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: {{ $kind }}
  name: {{ $name }}
subjects: {{ toYaml $val.subjects | nindent 2 }}
{{- end }}
{{- end }}
{{- end }}
