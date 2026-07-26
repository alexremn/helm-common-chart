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
