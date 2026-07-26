{{/*
=============================================================================
DEPLOY-TOOL DIALECT
Resolves which tool consumes the rendered manifests, and emits the ordering
and lifecycle metadata that tool understands.
=============================================================================
*/}}

{{/*
Resolve the active deploy tool.

Resolution order:
  1. .Values.global.deployTool           — explicit, validated
  2. .Values.global.werf.annotations     — deprecated boolean override
                                           (true -> werf, false -> generic)
  3. werf service values present         -> werf
  4. "generic"

werf injects its own service values on every deploy: `global.werf.version` and
`global.werf.name` always, `global.werf.env` when --env/$WERF_ENV is set, plus
a `werf` top-level map. Charts migrated from werf 1.x also hand-write
`werf.name` / `werf.env`; the bare presence of a `werf` key covers both.

ArgoCD cannot be detected: Helm exposes no `env` function, and nothing in
.Release or .Capabilities distinguishes ArgoCD's repo-server from a plain
`helm template`. ArgoCD consumers set global.deployTool explicitly, normally
once in an ApplicationSet template.

Usage: {{- $tool := include "common.deployTool" $ -}}
*/}}
{{- define "common.deployTool" -}}
{{- $values := include "common._values" . | fromYaml | default dict -}}
{{- $valid := list "generic" "werf" "argocd" -}}
{{- $explicit := dig "global" "deployTool" "" $values -}}
{{- $legacy := dig "global" "werf" "annotations" nil $values -}}
{{- if $explicit -}}
  {{- if not (has $explicit $valid) -}}
    {{- fail (printf "Unknown global.deployTool %q. Valid values: %s." $explicit (join ", " $valid)) -}}
  {{- end -}}
  {{- $explicit -}}
{{- else if not (kindIs "invalid" $legacy) -}}
  {{- ternary "werf" "generic" (eq $legacy true) -}}
{{- else if or (dig "global" "werf" "version" nil $values) (dig "global" "werf" "name" nil $values) (hasKey $values "werf") -}}
werf
{{- else -}}
generic
{{- end -}}
{{- end -}}

{{/*
Deploy-ordering annotation for the active dialect.

werf orders with `werf.io/weight`, ArgoCD with
`argocd.argoproj.io/sync-wave`. Both are lower-runs-first integers, so the
weight maps 1:1. Plain Helm needs nothing — its install order already puts
ConfigMaps and Secrets ahead of workloads.

Usage:
  {{- include "common.annotations.ordering" (dict "root" . "weight" -1) }}
*/}}
{{- define "common.annotations.ordering" -}}
{{- $tool := include "common.deployTool" .root -}}
{{- $weight := .weight | toString -}}
{{- if eq $tool "werf" -}}
werf.io/weight: {{ $weight | quote }}
{{- else if eq $tool "argocd" -}}
argocd.argoproj.io/sync-wave: {{ $weight | quote }}
{{- end -}}
{{- end -}}

{{/*
Workload lifecycle / rollout-tracking annotations for the active dialect.

werf tracks rollouts with `werf.io/no-activity-timeout` and
`werf.io/failures-allowed-per-replica`. ArgoCD has no per-resource
equivalent — retry patience lives in Application.spec.syncPolicy.retry — and
plain Helm has none either, so both emit nothing.

Usage:
  {{- include "common.annotations.lifecycle" $root }}
*/}}
{{- define "common.annotations.lifecycle" -}}
{{- if eq (include "common.deployTool" .) "werf" -}}
werf.io/no-activity-timeout: {{ default "6m" .timeout | quote }}
werf.io/failures-allowed-per-replica: {{ default "3" .failures | quote }}
{{- end -}}
{{- end -}}
